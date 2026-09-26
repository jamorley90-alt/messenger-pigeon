package transport

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"math/big"
	"net"
	"testing"
	"time"
)

func certificate(t *testing.T) (tls.Certificate, *x509.CertPool) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), DNSNames: []string{"relay.test"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, BasicConstraintsValid: true}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(parsed)
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}, roots
}
func handshake(t *testing.T, version uint16, curve tls.CurveID) error {
	t.Helper()
	cert, roots := certificate(t)
	serverSide, clientSide := net.Pipe()
	defer serverSide.Close()
	defer clientSide.Close()
	_ = serverSide.SetDeadline(time.Now().Add(3 * time.Second))
	_ = clientSide.SetDeadline(time.Now().Add(3 * time.Second))
	server := tls.Server(serverSide, ServerConfig(cert))
	client := tls.Client(clientSide, &tls.Config{MinVersion: version, MaxVersion: version, ServerName: "relay.test", RootCAs: roots, CurvePreferences: []tls.CurveID{curve}})
	done := make(chan error, 1)
	go func() { done <- server.Handshake() }()
	err := client.Handshake()
	serverErr := <-done
	if err != nil {
		return err
	}
	return serverErr
}
func TestTLS13HybridHandshake(t *testing.T) {
	if err := handshake(t, tls.VersionTLS13, tls.X25519MLKEM768); err != nil {
		t.Fatal(err)
	}
}
func TestClassicalOnlyRejected(t *testing.T) {
	if err := handshake(t, tls.VersionTLS13, tls.X25519); err == nil {
		t.Fatal("classical fallback allowed")
	}
}
func TestTLS12Rejected(t *testing.T) {
	if err := handshake(t, tls.VersionTLS12, tls.CurveP256); err == nil {
		t.Fatal("TLS 1.2 allowed")
	}
}
