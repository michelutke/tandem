// tools/mitm-lab/e15-10-cert-abuse/lib/mismatched_cert_server.go
//
// Impostor TLS 1.3 server that presents a certificate (the real Mac's genuine one, for E15-10
// scenario 6) while signing its own CertificateVerify with an *unrelated* private key -- see
// `mismatched_cert_client.go`'s header for why this requires building a `tls.Certificate` struct
// literal directly rather than any higher-level binding (all of which refuse to load a mismatched
// pair at all, including a raw OpenSSL C program -- verified empirically).
//
// Binds one listening socket on PORT, accepts exactly one connection, attempts the TLS server
// handshake (mTLS: requests and accepts any client certificate -- see below for why it must not
// validate it -- matching `ListenerFactory.swift`'s real configuration on the "requires a client
// cert" axis, though the point of failure here is the server's own CertificateVerify signature,
// which the connecting JVM client's TLS stack must reject before ever completing its own side),
// and exits. Never runs a second connection -- one-shot, like the shell `openssl s_server -naccept
// 1` convention this mitm-lab already uses elsewhere.
//
// `ClientAuth: tls.RequireAnyClientCert` deliberately requires a client certificate but never
// verifies it against any CA (there is no CA store configured at all): this impostor's own
// judgment about the client's certificate must never influence the scenario's outcome, which
// hinges entirely on whether the *client* (the real JVM harness, i.e. the phone) rejects *this*
// server's bad CertificateVerify signature -- not on whether this test double approves of the
// client's cert.
//
// usage: mismatched_cert_server PORT CERT_PEM KEY_PEM ALPN
// prints "LISTENING" once bound (so the driving script knows it is safe to dial), then exactly one
// of:
//
//	HANDSHAKE_OK
//	HANDSHAKE_FAILED <reason>
package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"net"
	"os"
	"time"
)

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
	privKey, err := x509.ParseECPrivateKey(keyBlock.Bytes)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("key did not parse as an EC private key: %w", err)
	}

	// Deliberately NOT tls.X509KeyPair(): see mismatched_cert_client.go's header.
	return tls.Certificate{
		Certificate: [][]byte{certBlock.Bytes},
		PrivateKey:  privKey,
	}, nil
}

func main() {
	if len(os.Args) != 5 {
		fmt.Fprintln(os.Stderr, "usage: mismatched_cert_server PORT CERT_PEM KEY_PEM ALPN")
		os.Exit(2)
	}
	port, certPath, keyPath, alpn := os.Args[1], os.Args[2], os.Args[3], os.Args[4]

	cert, err := loadMismatchedCertificate(certPath, keyPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "could not build mismatched cert: %v\n", err)
		os.Exit(1)
	}

	config := &tls.Config{
		MinVersion:   tls.VersionTLS13,
		MaxVersion:   tls.VersionTLS13,
		Certificates: []tls.Certificate{cert},
		NextProtos:   []string{alpn},
		// No CA pool, no VerifyPeerCertificate: this impostor never judges the client's cert (see
		// file header) -- it only requires that one be presented, matching the real Mac's mTLS
		// shape without adding a second, unrelated failure path.
		ClientAuth: tls.RequireAnyClientCert,
	}

	ln, err := net.Listen("tcp", "127.0.0.1:"+port)
	if err != nil {
		fmt.Fprintf(os.Stderr, "bind/listen failed on port %s: %v\n", port, err)
		os.Exit(1)
	}
	defer ln.Close()

	fmt.Println("LISTENING")
	os.Stdout.Sync()

	type acceptResult struct {
		conn net.Conn
		err  error
	}
	acceptCh := make(chan acceptResult, 1)
	go func() {
		conn, err := ln.Accept()
		acceptCh <- acceptResult{conn, err}
	}()

	var rawConn net.Conn
	select {
	case res := <-acceptCh:
		if res.err != nil {
			fmt.Printf("HANDSHAKE_FAILED accept error: %v\n", res.err)
			return
		}
		rawConn = res.conn
	case <-time.After(10 * time.Second):
		fmt.Println("HANDSHAKE_FAILED no client connected within timeout")
		return
	}
	defer rawConn.Close()
	_ = rawConn.SetDeadline(time.Now().Add(10 * time.Second))

	tconn := tls.Server(rawConn, config)
	// Server-side TLS 1.3: unlike the client, the server MUST receive and verify the client's
	// Finished (computed over the client's own Certificate/CertificateVerify) before its own
	// Handshake() call returns -- so, symmetrically to the client tool's post-handshake read, a bad
	// signature *this server* produces is what the real JVM client detects and reports back as a
	// rejection; what this server itself observes here is whatever alert the client sends in
	// response (RFC 8446 decrypt_error on a bad CertificateVerify), captured directly as this
	// Handshake() call's own error.
	if err := tconn.Handshake(); err != nil {
		fmt.Printf("HANDSHAKE_FAILED %s\n", err.Error())
		return
	}
	// A successful Handshake() alone isn't enough for a *client* dialing this server to tell
	// "genuinely accepted" apart from "the connection just closed with nothing said" (this
	// matters for the positive-control case: a matched cert+key pair must produce visible,
	// distinguishable success, not merely the absence of a signature-rejection alert). Write one
	// byte so a client's post-handshake read (mismatched_cert_client.go's own technique, applied
	// here in reverse) sees real application data.
	_, _ = tconn.Write([]byte{0})
	fmt.Println("HANDSHAKE_OK")
}
