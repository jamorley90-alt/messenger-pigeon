// Package transport defines the intended TLS endpoint policy independently of
// the development HTTP server. It is not evidence of a deployed configuration.
package transport

import "crypto/tls"

func ServerConfig(certificate tls.Certificate) *tls.Config {
	return &tls.Config{
		MinVersion:             tls.VersionTLS13,
		MaxVersion:             tls.VersionTLS13,
		CurvePreferences:       []tls.CurveID{tls.X25519MLKEM768},
		Certificates:           []tls.Certificate{certificate},
		SessionTicketsDisabled: true,
		NextProtos:             []string{"h2", "http/1.1"},
	}
}
