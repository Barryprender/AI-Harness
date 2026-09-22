// Command example is a stub HTTP service.
//
// It exists so the harness has something real to govern. Break it on purpose —
// misformat it, add an unused variable, make the test fail — and watch the
// gates react. That is the whole job of this package.
package main

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
	"os"
	"time"
)

func main() {
	addr := listenAddr(os.Getenv("PORT"))

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health)

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("listening on %s", addr)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}

// listenAddr turns the PORT environment variable into a listen address.
//
// It binds the loopback interface, not every interface: a stub service that
// nobody has thought about should not be reachable from the network. An empty
// or malformed PORT falls back to 8080 rather than failing, because the default
// has to work with no configuration at all.
func listenAddr(port string) string {
	if port == "" {
		return "127.0.0.1:8080"
	}
	if _, err := net.LookupPort("tcp", port); err != nil {
		log.Printf("PORT=%q is not a valid port, using 8080", port)
		return "127.0.0.1:8080"
	}
	return net.JoinHostPort("127.0.0.1", port)
}

func health(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok"}); err != nil {
		log.Printf("writing health response: %v", err)
	}
}
