// tools/mitm-lab/e70-09-rotation/lib/rotation_before_hello_client.go
//
// Real TLS 1.3 mTLS client (genuine, matched cert/key) that, once the handshake completes, sends one
// hand-built CONTROL-channel `Envelope{KeyRotation}` frame as its very first frame -- before any
// `VersionHello` -- using the wire format `docs/protocol/SPEC.md #framing-and-envelope` defines (u32
// big-endian length prefix + serialized `Envelope`; `envelope.proto`: channel=1, seq=2,
// key_rotation=111; `rotation.proto`'s `KeyRotation`: new_spki_der=1, sig_old_key=2, sig_new_key=3).
// The real Swift/Kotlin clients always send `VersionHello` first, so no real client library can
// produce this frame order (same reason as E15-11's version_hello_client.go).
//
// The `KeyRotation` is as well-formed as a harness can make it without a `RotationChallenge` (none
// is ever sent before Ready): a fresh P-256 new key, and both signatures made over the real SPEC.md
// transcript `"tandem-rotate-v1" || LP(oldSpki) || LP(newSpki) || LP(cb)` with an all-zero `cb`,
// the old signature by the certificate's own key. Anything the peer does with it other than closing
// the connection or rejecting it is therefore a real finding, not a malformed-frame artifact.
//
// usage: rotation_before_hello_client HOST PORT CERT_PEM KEY_PEM ALPN READ_TIMEOUT_MS
// prints HANDSHAKE_FAILED <reason>, or HANDSHAKE_OK, SENT_ENVELOPE <hex>, one FRAME_PAYLOAD <field
// number> line per frame received (4 = VersionHello, 112 = RotationAck, 113 = RotationReject), then
// CLOSED_MS <n> or STILL_OPEN_AFTER_MS <n>.
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"time"
)

const (
	channelControl       = 1
	keyRotationFieldNum  = 111
	wireTypeVarint       = 0
	wireTypeLengthPrefix = 2
	maxFrameBytes        = 1 << 20
)

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

func appendBytesField(dst []byte, fieldNumber int, value []byte) []byte {
	dst = appendTag(dst, fieldNumber, wireTypeLengthPrefix)
	dst = appendVarint(dst, uint64(len(value)))
	return append(dst, value...)
}

func lengthPrefixed(value []byte) []byte {
	return append([]byte{byte(len(value) >> 8), byte(len(value))}, value...)
}

func sign(key *ecdsa.PrivateKey, message []byte) []byte {
	digest := sha256.Sum256(message)
	signature, err := ecdsa.SignASN1(rand.Reader, key, digest[:])
	if err != nil {
		panic(err)
	}
	return signature
}

func encodeKeyRotationEnvelope(oldKey *ecdsa.PrivateKey) []byte {
	newKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	oldSpki, err := x509.MarshalPKIXPublicKey(&oldKey.PublicKey)
	if err != nil {
		panic(err)
	}
	newSpki, err := x509.MarshalPKIXPublicKey(&newKey.PublicKey)
	if err != nil {
		panic(err)
	}
	transcript := []byte("tandem-rotate-v1")
	transcript = append(transcript, lengthPrefixed(oldSpki)...)
	transcript = append(transcript, lengthPrefixed(newSpki)...)
	transcript = append(transcript, lengthPrefixed(make([]byte, 32))...)

	var keyRotation []byte
	keyRotation = appendBytesField(keyRotation, 1, newSpki)
	keyRotation = appendBytesField(keyRotation, 2, sign(oldKey, transcript))
	keyRotation = appendBytesField(keyRotation, 3, sign(newKey, transcript))

	var envelope []byte
	envelope = appendTag(envelope, 1, wireTypeVarint)
	envelope = appendVarint(envelope, channelControl)
	envelope = appendTag(envelope, 2, wireTypeVarint)
	envelope = appendVarint(envelope, 1)
	return appendBytesField(envelope, keyRotationFieldNum, keyRotation)
}

func encodeFrame(envelope []byte) []byte {
	n := len(envelope)
	return append([]byte{byte(n >> 24), byte(n >> 16), byte(n >> 8), byte(n)}, envelope...)
}

// Returns the field number of the first length-delimited field of an Envelope (its payload oneof).
func payloadFieldNumber(envelope []byte) int {
	for i := 0; i < len(envelope); {
		tag, n := readVarint(envelope[i:])
		if n == 0 {
			return 0
		}
		i += n
		switch tag & 7 {
		case wireTypeVarint:
			_, n = readVarint(envelope[i:])
			if n == 0 {
				return 0
			}
			i += n
		case wireTypeLengthPrefix:
			return int(tag >> 3)
		default:
			return 0
		}
	}
	return 0
}

func readVarint(b []byte) (uint64, int) {
	var v uint64
	for i := 0; i < len(b) && i < 10; i++ {
		v |= uint64(b[i]&0x7f) << (7 * uint(i))
		if b[i] < 0x80 {
			return v, i + 1
		}
	}
	return 0, 0
}

func main() {
	if len(os.Args) != 7 {
		fmt.Fprintln(os.Stderr, "usage: rotation_before_hello_client HOST PORT CERT_PEM KEY_PEM ALPN READ_TIMEOUT_MS")
		os.Exit(2)
	}
	host, port, certPath, keyPath, alpn := os.Args[1], os.Args[2], os.Args[3], os.Args[4], os.Args[5]
	readTimeoutMs, err := strconv.Atoi(os.Args[6])
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED bad READ_TIMEOUT_MS argument: %v\n", err)
		return
	}
	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED could not load cert/key: %v\n", err)
		return
	}
	certKey, ok := cert.PrivateKey.(*ecdsa.PrivateKey)
	if !ok {
		fmt.Println("HANDSHAKE_FAILED cert key is not ECDSA")
		return
	}

	rawConn, err := net.DialTimeout("tcp", net.JoinHostPort(host, port), 6*time.Second)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED TCP connect failed: %v\n", err)
		return
	}
	defer rawConn.Close()

	tconn := tls.Client(rawConn, &tls.Config{
		MinVersion:         tls.VersionTLS13,
		MaxVersion:         tls.VersionTLS13,
		Certificates:       []tls.Certificate{cert},
		InsecureSkipVerify: true, // this tool probes the PEER's reaction; it never trusts the peer itself.
		NextProtos:         []string{alpn},
		ServerName:         host,
	})
	_ = tconn.SetDeadline(time.Now().Add(6 * time.Second))
	if err := tconn.Handshake(); err != nil {
		fmt.Printf("HANDSHAKE_FAILED %s\n", err.Error())
		return
	}
	fmt.Println("HANDSHAKE_OK")

	envelope := encodeKeyRotationEnvelope(certKey)
	if _, err := tconn.Write(encodeFrame(envelope)); err != nil {
		fmt.Printf("SEND_FAILED %v\n", err)
		return
	}
	fmt.Printf("SENT_ENVELOPE %s\n", hex.EncodeToString(envelope))

	deadline := time.Now().Add(time.Duration(readTimeoutMs) * time.Millisecond)
	_ = tconn.SetReadDeadline(deadline)
	sendAt := time.Now()
	for {
		header := make([]byte, 4)
		if _, readErr := io.ReadFull(tconn, header); readErr != nil {
			reportEnd(readErr, sendAt)
			return
		}
		length := int(header[0])<<24 | int(header[1])<<16 | int(header[2])<<8 | int(header[3])
		if length > maxFrameBytes {
			fmt.Printf("CLOSED_MS %d\n", time.Since(sendAt).Milliseconds())
			return
		}
		body := make([]byte, length)
		if _, readErr := io.ReadFull(tconn, body); readErr != nil {
			reportEnd(readErr, sendAt)
			return
		}
		fmt.Printf("FRAME_PAYLOAD %d\n", payloadFieldNumber(body))
	}
}

func reportEnd(readErr error, sendAt time.Time) {
	if e, ok := readErr.(net.Error); ok && e.Timeout() {
		fmt.Printf("STILL_OPEN_AFTER_MS %d\n", time.Since(sendAt).Milliseconds())
		return
	}
	fmt.Printf("CLOSED_MS %d\n", time.Since(sendAt).Milliseconds())
}
