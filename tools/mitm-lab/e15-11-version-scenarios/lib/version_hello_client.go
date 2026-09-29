// tools/mitm-lab/e15-11-version-scenarios/lib/version_hello_client.go
//
// Real TLS 1.3 mTLS client (genuine, matched cert/key -- unlike E15-10's mismatched-cert tooling,
// there is nothing to fake here) that, once the handshake completes, sends exactly one hand-built
// CONTROL-channel `Envelope{VersionHello{major}}` frame -- the wire format `docs/protocol/SPEC.md
// #framing-and-envelope` defines (`u32 big-endian length prefix` + serialized `Envelope` bytes) --
// then reads until the peer closes the connection or a deadline elapses.
//
// This exists because no scripting-language TLS binding this mitm-lab already uses (`openssl
// s_client`, Ruby/Python bindings) can construct and send an arbitrary application-layer frame of
// this protocol: only the real Swift/Kotlin implementations speak it, and both of those always
// send a *correct* `VersionHello` as their very first CONTROL frame, automatically, the instant a
// session exists (`VersionHandshake.perform()`/`.run()` -- there is no seam to override the major
// version through the real client library, by design). Encoding one `Envelope{VersionHello{...}}`
// by hand is small and stable enough not to need full protobuf codegen: `envelope.proto` assigns
// channel=field 1 (varint), seq=field 2 (varint), version_hello=field 4 (length-delimited), and
// `control.proto`'s `VersionHello` assigns major=field 1 (varint) -- see this tool's own
// `encodeEnvelope`.
//
// `docs/protocol/SPEC.md #errors-and-close-codes` states plainly that `VERSION_MISMATCH` carries
// no wire signal at all (the peer only ever observes the connection close). This tool substitutes
// for that missing signal by construction, not by inference: run it once with an unsupported major
// (a well-formed frame, sent promptly) and once with `major=1` (this protocol's real value) against
// the same real Mac listener. A close within a couple of seconds in the first case, but not the
// second, isolates "wrong major" as the only variable that changed -- ruling out `PROTOCOL_TIMEOUT`
// (VersionHandshake's own 5 s deadline, comfortably longer) and `MALFORMED_FRAME`/`DECODE_FAILED`
// (the major=1 case proves this tool's own encoding is accepted). The scenario script that drives
// this tool is what actually performs and interprets that A/B comparison.
//
// ALPN may be the literal string "none" to send no ALPN extension at all (NextProtos left nil)
// rather than a specific protocol name -- reused by the ALPN-mismatch scenario's no-ALPN case with
// this same timing-discriminator approach.
//
// usage: version_hello_client HOST PORT CERT_PEM KEY_PEM ALPN MAJOR READ_TIMEOUT_MS
// prints one of:
//
//	HANDSHAKE_FAILED <reason>
//
// or, on a successful handshake:
//
//	HANDSHAKE_OK
//	SENT_ENVELOPE <hex>
//	CLOSED_MS <n>
//	STILL_OPEN_AFTER_MS <n>
package main

import (
	"crypto/tls"
	"encoding/hex"
	"fmt"
	"net"
	"os"
	"strconv"
	"time"
)

func nowMs(start time.Time) int64 {
	return time.Since(start).Milliseconds()
}

// varint (protobuf base-128) encoding of a non-negative value that fits in a uint32 -- every field
// this tool ever encodes (channel, seq, major) is small enough for the simple single/double-byte
// cases, but this handles the general case anyway rather than assuming that.
func appendVarint(dst []byte, v uint64) []byte {
	for v >= 0x80 {
		dst = append(dst, byte(v)|0x80)
		v >>= 7
	}
	return append(dst, byte(v))
}

func appendTag(dst []byte, fieldNumber int, wireType byte) []byte {
	return appendVarint(dst, uint64(fieldNumber)<<3|uint64(wireType))
}

// Builds one serialized `tandem.v1.Envelope` carrying `channel=CHANNEL_CONTROL (1)`, `seq=1` (the
// first frame this connection's CONTROL channel ever sends, SPEC.md #framing-and-envelope), and
// `version_hello=VersionHello{major=major}` (minor/capabilities left at their proto3 zero default,
// which proto3 always omits on the wire).
func encodeEnvelope(major uint32) []byte {
	var versionHello []byte
	versionHello = appendTag(versionHello, 1, 0) // VersionHello.major, varint
	versionHello = appendVarint(versionHello, uint64(major))

	var envelope []byte
	envelope = appendTag(envelope, 1, 0) // Envelope.channel, varint
	envelope = appendVarint(envelope, 1) // CHANNEL_CONTROL
	envelope = appendTag(envelope, 2, 0) // Envelope.seq, varint
	envelope = appendVarint(envelope, 1)
	envelope = appendTag(envelope, 4, 2) // Envelope.version_hello, length-delimited
	envelope = appendVarint(envelope, uint64(len(versionHello)))
	envelope = append(envelope, versionHello...)
	return envelope
}

// u32 big-endian length prefix + envelope bytes, exactly `docs/protocol/SPEC.md
// #framing-and-envelope`'s frame format.
func encodeFrame(envelope []byte) []byte {
	n := len(envelope)
	frame := []byte{byte(n >> 24), byte(n >> 16), byte(n >> 8), byte(n)}
	return append(frame, envelope...)
}

func main() {
	if len(os.Args) != 8 {
		fmt.Fprintln(os.Stderr, "usage: version_hello_client HOST PORT CERT_PEM KEY_PEM ALPN MAJOR READ_TIMEOUT_MS")
		os.Exit(2)
	}
	host, port, certPath, keyPath, alpn := os.Args[1], os.Args[2], os.Args[3], os.Args[4], os.Args[5]
	majorArg, err := strconv.ParseUint(os.Args[6], 10, 32)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED bad MAJOR argument: %v\n", err)
		return
	}
	readTimeoutMs, err := strconv.Atoi(os.Args[7])
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED bad READ_TIMEOUT_MS argument: %v\n", err)
		return
	}

	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED could not load cert/key: %v\n", err)
		return
	}

	rawConn, err := net.DialTimeout("tcp", net.JoinHostPort(host, port), 6*time.Second)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED TCP connect failed: %v\n", err)
		return
	}
	defer rawConn.Close()

	var nextProtos []string
	if alpn != "none" {
		nextProtos = []string{alpn}
	}
	tconn := tls.Client(rawConn, &tls.Config{
		MinVersion:         tls.VersionTLS13,
		MaxVersion:         tls.VersionTLS13,
		Certificates:       []tls.Certificate{cert},
		InsecureSkipVerify: true, // this tool probes the PEER's reaction; it never trusts the peer itself.
		NextProtos:         nextProtos,
		ServerName:         host,
	})
	_ = tconn.SetDeadline(time.Now().Add(6 * time.Second))
	if err := tconn.Handshake(); err != nil {
		fmt.Printf("HANDSHAKE_FAILED %s\n", err.Error())
		return
	}
	fmt.Println("HANDSHAKE_OK")

	envelope := encodeEnvelope(uint32(majorArg))
	frame := encodeFrame(envelope)
	if _, err := tconn.Write(frame); err != nil {
		fmt.Printf("SEND_FAILED %v\n", err)
		return
	}
	fmt.Printf("SENT_ENVELOPE %s\n", hex.EncodeToString(envelope))

	_ = tconn.SetReadDeadline(time.Now().Add(time.Duration(readTimeoutMs) * time.Millisecond))
	sendAt := time.Now()
	buf := make([]byte, 4096)
	for {
		n, readErr := tconn.Read(buf)
		if n > 0 {
			// Any application bytes back are still evidence the connection stayed open at least
			// that long; keep reading toward the same deadline rather than treating this as close.
			continue
		}
		if readErr != nil {
			if e, ok := readErr.(net.Error); ok && e.Timeout() {
				fmt.Printf("STILL_OPEN_AFTER_MS %d\n", nowMs(sendAt))
				return
			}
			fmt.Printf("CLOSED_MS %d\n", nowMs(sendAt))
			return
		}
	}
}
