package main

import (
	"net/http"
	"net/http/httptest"
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
