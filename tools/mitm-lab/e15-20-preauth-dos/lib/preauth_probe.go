// tools/mitm-lab/e15-20-preauth-dos/lib/preauth_probe.go
//
// Source-address-bound pre-authentication probe for the E15-20 DoS scenarios. Every mode dials
// from an explicit local source IP (a loopback alias 127.0.0.2..127.0.0.9) so a scenario can act
// as several distinct sources against the real Mac listener; no shell/openssl client can both pick
// the source address and hold many sockets open at once.
//
// usage: preauth_probe MODE SRC_IP HOST PORT [MODE ARGS...]
//
//	tcp-silent  WAIT_MS               TCP connect, send nothing
//	tls-silent  CERT KEY WAIT_MS      complete mTLS (tandem/1), send no VersionHello
//	hold        COUNT WAIT_MS         open COUNT TCP connections and keep them idle
//	burst       COUNT                 COUNT TCP connect-then-close attempts, one after another
//	ready       CERT KEY WAIT_MS      mTLS + VersionHello(1), wait for the peer's first frame
//
// prints, per mode:
//
//	tcp-silent/tls-silent: [HANDSHAKE_OK] then CLOSED_MS <n> | STILL_OPEN_AFTER_MS <n>
//	                       (tls-silent measures from TLS completion), or CONNECT_FAILED/HANDSHAKE_FAILED <reason>
//	hold:   SETTLED OPEN <n> CLOSED <n>  (after a 1.5 s settle), then FINISHED after WAIT_MS
//	burst:  BURST_DONE <n>
//	ready:  READY_MS <n> | HANDSHAKE_FAILED <reason> | NO_FRAME_AFTER_MS <n> | CONNECT_FAILED <reason>
package main

import (
	"crypto/tls"
	"fmt"
	"net"
	"os"
	"strconv"
	"sync"
	"time"
)

const (
	tandemALPN   = "tandem/1"
	settleDelay  = 1500 * time.Millisecond
	dialTimeout  = 6 * time.Second
	handshakeCap = 6 * time.Second
)

func dial(src, host, port string) (net.Conn, error) {
	d := net.Dialer{
		Timeout:   dialTimeout,
		LocalAddr: &net.TCPAddr{IP: net.ParseIP(src)},
	}
	return d.Dial("tcp", net.JoinHostPort(host, port))
}

func mustAtoi(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		fmt.Fprintf(os.Stderr, "bad integer argument %q\n", s)
		os.Exit(2)
	}
	return n
}

func tlsClient(conn net.Conn, certPath, keyPath, host string) (*tls.Conn, error) {
	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		return nil, err
	}
	return tls.Client(conn, &tls.Config{
		MinVersion:         tls.VersionTLS13,
		MaxVersion:         tls.VersionTLS13,
		Certificates:       []tls.Certificate{cert},
		InsecureSkipVerify: true,
		NextProtos:         []string{tandemALPN},
		ServerName:         host,
	}), nil
}

// Reads until the peer closes or the deadline elapses; prints how long the connection stayed open.
func reportClose(conn net.Conn, waitMs int) {
	start := time.Now()
	_ = conn.SetReadDeadline(start.Add(time.Duration(waitMs) * time.Millisecond))
	buf := make([]byte, 4096)
	for {
		if _, err := conn.Read(buf); err != nil {
			elapsed := time.Since(start).Milliseconds()
			if e, ok := err.(net.Error); ok && e.Timeout() {
				fmt.Printf("STILL_OPEN_AFTER_MS %d\n", elapsed)
			} else {
				fmt.Printf("CLOSED_MS %d\n", elapsed)
			}
			return
		}
	}
}

func tcpSilent(src, host, port string, args []string) {
	conn, err := dial(src, host, port)
	if err != nil {
		fmt.Printf("CONNECT_FAILED %v\n", err)
		return
	}
	defer conn.Close()
	reportClose(conn, mustAtoi(args[0]))
}

func tlsSilent(src, host, port string, args []string) {
	conn, err := dial(src, host, port)
	if err != nil {
		fmt.Printf("CONNECT_FAILED %v\n", err)
		return
	}
	defer conn.Close()
	tconn, err := tlsClient(conn, args[0], args[1], host)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED %v\n", err)
		return
	}
	_ = tconn.SetDeadline(time.Now().Add(handshakeCap))
	if err := tconn.Handshake(); err != nil {
		fmt.Printf("HANDSHAKE_FAILED %v\n", err)
		return
	}
	fmt.Println("HANDSHAKE_OK")
	reportClose(tconn, mustAtoi(args[2]))
}

// A held connection is "closed" once a read returns EOF or a reset; a read deadline timeout means
// the Mac accepted it and is still waiting on it.
func isOpen(conn net.Conn) bool {
	_ = conn.SetReadDeadline(time.Now().Add(150 * time.Millisecond))
	_, err := conn.Read(make([]byte, 1))
	if err == nil {
		return false
	}
	e, ok := err.(net.Error)
	return ok && e.Timeout()
}

func hold(src, host, port string, args []string) {
	count, waitMs := mustAtoi(args[0]), mustAtoi(args[1])
	conns := make([]net.Conn, count)
	var wg sync.WaitGroup
	for i := range conns {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			if c, err := dial(src, host, port); err == nil {
				conns[i] = c
			}
		}(i)
	}
	wg.Wait()
	time.Sleep(settleDelay)
	open, closed := 0, 0
	for _, c := range conns {
		if c != nil && isOpen(c) {
			open++
		} else {
			closed++
		}
	}
	fmt.Printf("SETTLED OPEN %d CLOSED %d\n", open, closed)
	time.Sleep(time.Duration(waitMs) * time.Millisecond)
	for _, c := range conns {
		if c != nil {
			c.Close()
		}
	}
	fmt.Println("FINISHED")
}

func burst(src, host, port string, args []string) {
	count := mustAtoi(args[0])
	for i := 0; i < count; i++ {
		if c, err := dial(src, host, port); err == nil {
			c.Close()
		}
		time.Sleep(50 * time.Millisecond)
	}
	fmt.Printf("BURST_DONE %d\n", count)
}

// Same tiny hand-built Envelope{VersionHello{major=1}} frame as e15-11's version_hello_client.go.
func versionHelloFrame() []byte {
	envelope := []byte{0x08, 0x01, 0x10, 0x01, 0x22, 0x02, 0x08, 0x01}
	return append([]byte{0, 0, 0, byte(len(envelope))}, envelope...)
}

func ready(src, host, port string, args []string) {
	conn, err := dial(src, host, port)
	if err != nil {
		fmt.Printf("CONNECT_FAILED %v\n", err)
		return
	}
	defer conn.Close()
	tconn, err := tlsClient(conn, args[0], args[1], host)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED %v\n", err)
		return
	}
	start := time.Now()
	_ = tconn.SetDeadline(start.Add(handshakeCap))
	if err := tconn.Handshake(); err != nil {
		fmt.Printf("HANDSHAKE_FAILED %v\n", err)
		return
	}
	if _, err := tconn.Write(versionHelloFrame()); err != nil {
		fmt.Printf("HANDSHAKE_FAILED %v\n", err)
		return
	}
	_ = tconn.SetReadDeadline(time.Now().Add(time.Duration(mustAtoi(args[2])) * time.Millisecond))
	if _, err := tconn.Read(make([]byte, 1)); err != nil {
		fmt.Printf("NO_FRAME_AFTER_MS %d\n", time.Since(start).Milliseconds())
		return
	}
	fmt.Printf("READY_MS %d\n", time.Since(start).Milliseconds())
}

func main() {
	if len(os.Args) < 5 {
		fmt.Fprintln(os.Stderr, "usage: preauth_probe MODE SRC_IP HOST PORT [ARGS...]")
		os.Exit(2)
	}
	mode, src, host, port, args := os.Args[1], os.Args[2], os.Args[3], os.Args[4], os.Args[5:]
	modes := map[string]func(string, string, string, []string){
		"tcp-silent": tcpSilent, "tls-silent": tlsSilent, "hold": hold, "burst": burst, "ready": ready,
	}
	run, ok := modes[mode]
	if !ok {
		fmt.Fprintf(os.Stderr, "unknown mode %q\n", mode)
		os.Exit(2)
	}
	run(src, host, port, args)
}
