// tools/mitm-lab/e15-11-version-scenarios/lib/ticket_probe_server.go
//
// A scripted TLS 1.3 server (E15-11 scenario 5, Cycle 4) that accepts a real mTLS handshake from
// the real JVM harness client (the same `core/crypto`/`core/transport` code Android's app runs,
// E15-15), lets Go's own `crypto/tls` issue this connection's real `NewSessionTicket` messages
// (its default behavior -- `SessionTicketsDisabled` is left at its `false` zero value), then
// accepts a *second* connection from the same client and inspects that connection's raw
// `ClientHello` extensions for `pre_shared_key` (41) or `early_data` (42) -- proof the client never
// attempts session resumption even when a peer hands it a real ticket
// (`SslClientFactory`'s own kdoc already claims this: "a fresh SSLContext is created per
// connection... the client never offers a PSK identity on a subsequent connection"; this tool
// verifies that claim empirically rather than trusting the comment, same E15-10 lesson).
//
// The second connection is inspected at the raw-bytes level, not via `crypto/tls` itself:
// `tls.ClientHelloInfo` (the only hook `GetConfigForClient` exposes) does not surface the raw
// extension-type list, and there is nothing to gain from actually completing that handshake --
// this tool only needs to see what the client offered. `parseClientHelloExtensions` reads the TLS
// record/handshake headers itself (both always cleartext in a ClientHello) and lists the
// extension-type numbers present, per RFC 8446 §4.1.2.
//
// usage: ticket_probe_server PORT CERT_PEM KEY_PEM ALPN
// prints, once done:
//
//	LISTENING
//	HANDSHAKE1_FAILED <reason>            (fatal)
//	HANDSHAKE1_OK
//	CLIENTHELLO2_READ_FAILED <reason>     (fatal)
//	CLIENTHELLO2_EXTENSIONS <comma-separated decimal extension-type list>
//	CLIENTHELLO2_PSK <true|false>
//	CLIENTHELLO2_EARLYDATA <true|false>
package main

import (
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"time"
)

const (
	extPreSharedKey = 41
	extEarlyData    = 42
)

func readFull(r io.Reader, n int) ([]byte, error) {
	buf := make([]byte, n)
	if _, err := io.ReadFull(r, buf); err != nil {
		return nil, err
	}
	return buf, nil
}

// Reads one or more TLS records of content-type Handshake (0x16) from `conn`, accumulating
// handshake bytes until a complete ClientHello handshake message (its own 4-byte header, msg
// type + 3-byte length, followed by that many body bytes) has arrived, and returns the message
// body (after the 4-byte handshake header). A real ClientHello from any TLS stack this mitm-lab
// has observed fits in a single TLS record; this still loops defensively rather than assuming that.
func readClientHelloBody(conn net.Conn) ([]byte, error) {
	var handshakeBytes []byte
	for {
		header, err := readFull(conn, 5)
		if err != nil {
			return nil, fmt.Errorf("record header: %w", err)
		}
		if header[0] != 0x16 {
			return nil, fmt.Errorf("expected a Handshake record (0x16), got content-type 0x%02x", header[0])
		}
		recordLen := int(binary.BigEndian.Uint16(header[3:5]))
		record, err := readFull(conn, recordLen)
		if err != nil {
			return nil, fmt.Errorf("record body (%d bytes): %w", recordLen, err)
		}
		handshakeBytes = append(handshakeBytes, record...)

		if len(handshakeBytes) < 4 {
			continue
		}
		if handshakeBytes[0] != 0x01 {
			return nil, fmt.Errorf("expected a ClientHello handshake message (type 1), got type %d", handshakeBytes[0])
		}
		bodyLen := int(handshakeBytes[1])<<16 | int(handshakeBytes[2])<<8 | int(handshakeBytes[3])
		if len(handshakeBytes) >= 4+bodyLen {
			return handshakeBytes[4 : 4+bodyLen], nil
		}
	}
}

// Parses a ClientHello body (RFC 8446 §4.1.2) far enough to list its extension-type numbers:
// client_version(2) + random(32) + session_id (1-byte length prefix) + cipher_suites (2-byte
// length prefix) + compression_methods (1-byte length prefix) + extensions (2-byte length prefix,
// each extension itself a 2-byte type + 2-byte length + that many bytes).
func parseClientHelloExtensions(body []byte) ([]uint16, error) {
	pos := 2 + 32 // client_version + random
	if pos >= len(body) {
		return nil, fmt.Errorf("body too short for client_version+random")
	}
	sessionIDLen := int(body[pos])
	pos += 1 + sessionIDLen
	if pos+2 > len(body) {
		return nil, fmt.Errorf("body too short for cipher_suites length")
	}
	cipherSuitesLen := int(binary.BigEndian.Uint16(body[pos : pos+2]))
	pos += 2 + cipherSuitesLen
	if pos >= len(body) {
		return nil, fmt.Errorf("body too short for compression_methods length")
	}
	compressionLen := int(body[pos])
	pos += 1 + compressionLen
	if pos+2 > len(body) {
		return nil, fmt.Errorf("body too short for extensions length")
	}
	extensionsLen := int(binary.BigEndian.Uint16(body[pos : pos+2]))
	pos += 2
	end := pos + extensionsLen
	if end > len(body) {
		return nil, fmt.Errorf("extensions length %d overruns body", extensionsLen)
	}

	var types []uint16
	for pos+4 <= end {
		extType := binary.BigEndian.Uint16(body[pos : pos+2])
		extLen := int(binary.BigEndian.Uint16(body[pos+2 : pos+4]))
		types = append(types, extType)
		pos += 4 + extLen
	}
	return types, nil
}

func contains(types []uint16, want uint16) bool {
	for _, t := range types {
		if t == want {
			return true
		}
	}
	return false
}

func formatTypes(types []uint16) string {
	parts := make([]string, len(types))
	for i, t := range types {
		parts[i] = fmt.Sprintf("%d", t)
	}
	return strings.Join(parts, ",")
}

func main() {
	if len(os.Args) != 5 {
		fmt.Fprintln(os.Stderr, "usage: ticket_probe_server PORT CERT_PEM KEY_PEM ALPN")
		os.Exit(2)
	}
	port, certPath, keyPath, alpn := os.Args[1], os.Args[2], os.Args[3], os.Args[4]

	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		fmt.Printf("HANDSHAKE1_FAILED could not load cert/key: %v\n", err)
		return
	}

	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS13,
		MaxVersion:   tls.VersionTLS13,
		ClientAuth:   tls.RequireAnyClientCert, // invariant 3: this tool only cares that A cert was presented, never its chain.
		NextProtos:   []string{alpn},
		// SessionTicketsDisabled left at its zero value (false): this connection's own
		// NewSessionTicket messages are Go's real, unmodified TLS 1.3 server behavior.
	}

	listener, err := tls.Listen("tcp", net.JoinHostPort("", port), config)
	if err != nil {
		fmt.Printf("HANDSHAKE1_FAILED could not listen: %v\n", err)
		return
	}
	defer listener.Close()
	fmt.Println("LISTENING")

	conn1, err := listener.Accept()
	if err != nil {
		fmt.Printf("HANDSHAKE1_FAILED accept: %v\n", err)
		return
	}
	tconn1 := conn1.(*tls.Conn)
	_ = tconn1.SetDeadline(time.Now().Add(10 * time.Second))
	if err := tconn1.Handshake(); err != nil {
		fmt.Printf("HANDSHAKE1_FAILED %v\n", err)
		tconn1.Close()
		return
	}
	fmt.Println("HANDSHAKE1_OK")
	// Give Go's TLS 1.3 server state machine a moment to flush its post-handshake
	// NewSessionTicket writes (sent as part of the handshake goroutine, not gated on this tool
	// writing/reading application data) before tearing the connection down.
	time.Sleep(300 * time.Millisecond)
	tconn1.Close()

	// `tls.Listener.Accept()` hands back a `*tls.Conn` that only performs its handshake lazily on
	// first Read/Write -- `acceptRaw` unwraps it to the underlying raw connection instead, since
	// this tool needs the second connection's *raw* ClientHello bytes, never a completed handshake.
	conn2, err := acceptRaw(listener)
	if err != nil {
		fmt.Printf("CLIENTHELLO2_READ_FAILED accept: %v\n", err)
		return
	}
	defer conn2.Close()
	_ = conn2.SetDeadline(time.Now().Add(10 * time.Second))

	body, err := readClientHelloBody(conn2)
	if err != nil {
		fmt.Printf("CLIENTHELLO2_READ_FAILED %v\n", err)
		return
	}
	types, err := parseClientHelloExtensions(body)
	if err != nil {
		fmt.Printf("CLIENTHELLO2_READ_FAILED %v\n", err)
		return
	}
	fmt.Printf("CLIENTHELLO2_EXTENSIONS %s\n", formatTypes(types))
	fmt.Printf("CLIENTHELLO2_PSK %t\n", contains(types, extPreSharedKey))
	fmt.Printf("CLIENTHELLO2_EARLYDATA %t\n", contains(types, extEarlyData))
	// No response is ever sent: this tool only needs to see the ClientHello, and closing here
	// (rather than replying) makes the client's own handshake attempt fail fast instead of idling
	// out its own handshake-timeout deadline.
}

// Accepts the next connection on `listener` (a `tls.Listener`) as a raw `net.Conn`, without ever
// triggering `crypto/tls`'s own lazy handshake -- `tls.Listener.Accept()` always returns a
// `*tls.Conn` wrapper, but nothing here calls `Handshake()`/`Read()`/`Write()` through that
// wrapper, so the only bytes this tool ever reads from `conn2` are the ones `readClientHelloBody`
// reads directly off the wrapped raw connection.
func acceptRaw(listener net.Listener) (net.Conn, error) {
	conn, err := listener.Accept()
	if err != nil {
		return nil, err
	}
	tconn, ok := conn.(*tls.Conn)
	if !ok {
		return conn, nil
	}
	return tconn.NetConn(), nil
}
