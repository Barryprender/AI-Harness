package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestHealthReportsOK(t *testing.T) {
	rec := httptest.NewRecorder()
	health(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got, want := rec.Body.String(), "{\"status\":\"ok\"}\n"; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
}

// An end-to-end check that needs something the machine may not have.
//
// It stands in for the test every real project has: the one that needs a
// database, a message broker or a generated file. Without that thing it skips,
// and a skipped test reports "ok" exactly like a passing one. That is the lie
// verify.sh exists to catch - run the full tier without HARNESS_EXAMPLE_E2E=1
// and it exits 2, could not run, rather than 0.
func TestHealthEndToEnd(t *testing.T) {
	if os.Getenv("HARNESS_EXAMPLE_E2E") == "" {
		t.Skip("HARNESS_EXAMPLE_E2E is not set")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/healthz")
	if err != nil {
		t.Fatalf("GET /healthz: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want %d", resp.StatusCode, http.StatusOK)
	}
}

// A port that is not a number, or a number outside the valid range, must not
// reach net.Listen. Both fall back to the default.
func TestListenAddr(t *testing.T) {
	cases := []struct {
		port string
		want string
	}{
		{"", "127.0.0.1:8080"},
		{"9000", "127.0.0.1:9000"},
		{"not-a-port", "127.0.0.1:8080"},
		{"70000", "127.0.0.1:8080"},
	}
	for _, c := range cases {
		if got := listenAddr(c.port); got != c.want {
			t.Errorf("listenAddr(%q) = %q, want %q", c.port, got, c.want)
		}
	}
}
