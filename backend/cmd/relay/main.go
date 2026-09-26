package main

import (
	"context"
	"flag"
	"log"
	"messengerpigeon/backend/internal/api"
	"net/http"
	"os"
	"os/signal"
	"time"
)

func main() {
	dev := flag.Bool("dev", false, "run the loopback-only, memory-only development API")
	flag.Parse()
	if !*dev {
		log.Fatal("Production startup blocked: cryptographic integration, durable account storage, transparency auditing and TLS policy are not release-verified. Use -dev only for local development.")
	}
	service := api.New(time.Now)
	server := &http.Server{Addr: "127.0.0.1:8080", Handler: service.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	go func() {
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				defer cancel()
				_ = server.Shutdown(shutdown)
				return
			case <-ticker.C:
				service.Sweep()
			}
		}
	}()
	log.Print("Development relay listening on loopback port 8080; no production security claim")
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal("relay stopped")
	}
}
