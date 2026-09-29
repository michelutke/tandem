// tools/mitm-lab/e15-10-cert-abuse/lib/mismatched_cert_client.go
//
// Real TLS 1.3 client that presents a certificate while signing the CertificateVerify with an
// *unrelated* private key (E15-10 scenarios 3/5: swapped/foreign-key CertificateVerify).
//
// Every high-level TLS binding this mitm-lab already uses (`openssl s_client`, Ruby's
// `OpenSSL::SSL::SSLContext`, Python's `ssl`, and -- verified empirically against OpenSSL 3.6.4 --
// even a hand-rolled OpenSSL C program loading the private key before the certificate) refuses to
// load a genuinely mismatched cert/key pair: OpenSSL's internal `ssl_set_cert()` calls
// `X509_check_private_key()` whenever both a certificate and a key end up attached to the same
// `CERT_PKEY` slot, and *silently drops the mismatched key* on failure while still reporting
// success -- there is no load order that avoids this in libssl.
//
// Go's `crypto/tls` performs the equivalent check only in the `tls.X509KeyPair()` convenience
// constructor. A `tls.Certificate` built directly as a struct literal -- `Certificate: [][]byte
// {certDER}, PrivateKey: someOtherKey` -- is never passed through that check, so this really does
// produce a `CertificateVerify` signed with a key that does not match the leaf certificate,
// reaching the wire for real. This is what makes the negative case in scenarios 3/5 meaningful:
// without a genuinely mismatched signature, the peer's rejection can't be distinguished from
// simply presenting no certificate at all (scenario 1).
//
// usage: mismatched_cert_client HOST PORT CERT_PEM KEY_PEM ALPN
// prints exactly one of:
//
//	HANDSHAKE_OK
//	HANDSHAKE_FAILED <reason>
//	HANDSHAKE_TIMEOUT <reason>
//
// and "ELAPSED_MS <n>" on the next line. HANDSHAKE_TIMEOUT (distinct from HANDSHAKE_FAILED) means
// the peer never responded within the read deadline -- a socket-read timeout is not evidence of
// rejection, and must never be reported as if it were (E15-10 finding: a silently-hanging peer is
// a real bug, not a passing test).
package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"time"
)

func nowMs(start time.Time) int64 {
	return time.Since(start).Milliseconds()
}

func loadMismatchedCertificate(certPath, keyPath string) (tls.Certificate, error) {
	certPEMBytes, err := os.ReadFile(certPath)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("could not read cert: %w", err)
	}
	certBlock, _ := pem.Decode(certPEMBytes)
	if certBlock == nil {
		return tls.Certificate{}, errors.New("could not decode cert PEM")
	}
	if _, err := x509.ParseCertificate(certBlock.Bytes); err != nil {
		return tls.Certificate{}, fmt.Errorf("cert did not parse as X.509: %w", err)
	}

	keyPEMBytes, err := os.ReadFile(keyPath)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("could not read key: %w", err)
	}
	keyBlock, _ := pem.Decode(keyPEMBytes)
	if keyBlock == nil {
		return tls.Certificate{}, errors.New("could not decode key PEM")
	}
	// gen-cert.sh (E15-08 self-test helper, reused as-is here) always produces `openssl ecparam
	// -genkey` SEC1 P-256 keys ("-----BEGIN EC PRIVATE KEY-----"), never PKCS8 -- no need to
	// handle other key encodings.
	privKey, err := x509.ParseECPrivateKey(keyBlock.Bytes)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("key did not parse as an EC private key: %w", err)
	}

	// Deliberately NOT tls.X509KeyPair(): that helper calls the Go equivalent of OpenSSL's
	// cross-check (comparing the parsed public key against the private key) and refuses a
	// mismatched pair. Constructing the struct directly skips it -- this is the whole point.
	return tls.Certificate{
		Certificate: [][]byte{certBlock.Bytes},
		PrivateKey:  privKey,
	}, nil
}

func isTimeout(err error) bool {
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}

func main() {
	if len(os.Args) != 6 {
		fmt.Fprintln(os.Stderr, "usage: mismatched_cert_client HOST PORT CERT_PEM KEY_PEM ALPN")
		os.Exit(2)
	}
	host, port, certPath, keyPath, alpn := os.Args[1], os.Args[2], os.Args[3], os.Args[4], os.Args[5]
	start := time.Now()

	cert, err := loadMismatchedCertificate(certPath, keyPath)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED could not build mismatched cert: %v\n", err)
		fmt.Printf("ELAPSED_MS %d\n", nowMs(start))
		return
	}

	rawConn, err := net.DialTimeout("tcp", net.JoinHostPort(host, port), 6*time.Second)
	if err != nil {
		fmt.Printf("HANDSHAKE_FAILED TCP connect failed: %v\n", err)
		fmt.Printf("ELAPSED_MS %d\n", nowMs(start))
		return
	}
	defer rawConn.Close()
	_ = rawConn.SetDeadline(time.Now().Add(6 * time.Second))

	tconn := tls.Client(rawConn, &tls.Config{
		MinVersion:         tls.VersionTLS13,
		MaxVersion:         tls.VersionTLS13,
		Certificates:       []tls.Certificate{cert},
		InsecureSkipVerify: true, // this tool probes the PEER's reaction; it never trusts the peer itself.
		NextProtos:         []string{alpn},
		ServerName:         host,
	})

	if err := tconn.Handshake(); err != nil {
		// TLS 1.3 subtlety (RFC 8446): a client's own Handshake() call can legitimately fail
		// synchronously too (e.g. the server rejects the ClientHello outright), so a hard failure
		// here is still a genuine result, not a bug in this tool.
		fmt.Printf("HANDSHAKE_FAILED %s\n", err.Error())
		fmt.Printf("ELAPSED_MS %d\n", nowMs(start))
		return
	}

	// The client side of a TLS 1.3 handshake completes locally (Handshake() returns nil) the
	// moment it has *sent* its own Certificate/CertificateVerify/Finished -- before the server has
	// verified any of it (RFC 8446 §4.4.1). A server that rejects this client's CertificateVerify
	// signature (exactly this scenario's attack) only surfaces that as a fatal alert closing the
	// connection shortly after, so Handshake() succeeding is never sufficient evidence of
	// acceptance; a post-handshake read for the alert is required.
	buf := make([]byte, 16)
	n, readErr := tconn.Read(buf)
	elapsed := nowMs(start)
	switch {
	case n > 0:
		fmt.Println("HANDSHAKE_OK")
	case isTimeout(readErr):
		// The peer never responded within the deadline: this is NOT evidence of a rejection --
		// conflating a timeout with "the peer rejected us" was exactly the bug this tool exists to
		// avoid (a silently-hanging, silently-accepting peer must fail this test loudly, not pass
		// it by accident).
		fmt.Printf("HANDSHAKE_TIMEOUT peer never responded within the read deadline: %v\n", readErr)
	case readErr != nil:
		reason := readErr.Error()
		if strings.Contains(strings.ToLower(reason), "alert") {
			fmt.Printf("HANDSHAKE_FAILED tls alert: %s\n", reason)
		} else {
			fmt.Printf("HANDSHAKE_FAILED post-handshake: %s\n", reason)
		}
	default:
		fmt.Println("HANDSHAKE_FAILED post-handshake: read returned 0 bytes with no error")
	}
	fmt.Printf("ELAPSED_MS %d\n", elapsed)
}
