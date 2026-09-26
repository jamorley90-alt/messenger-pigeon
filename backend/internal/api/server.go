package api

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"messengerpigeon/backend/internal/relay"
)

type account struct {
	ID, Username string
	auth         [32]byte
}
type invitation struct {
	ID, From, To string
	ExpiresAt    time.Time
}
type contact struct {
	Peer     string `json:"peer"`
	Username string `json:"username"`
	Token    string `json:"deliveryToken"`
}
type Server struct {
	// Account deletion takes an exclusive lock so an already-authenticated
	// request cannot mutate maps after its account has been removed.
	identityLifetime sync.RWMutex
	mu               sync.Mutex
	now              func() time.Time
	queue            *relay.Queue
	accounts         map[string]account
	usernames        map[string]string
	sessions         map[[32]byte]string
	invitations      map[string]invitation
	contacts         map[string]map[string]contact
	blocked          map[string]map[string]bool
	limits           map[string][]time.Time
}

func New(now func() time.Time) *Server {
	return &Server{now: now, queue: relay.New(2000, now), accounts: map[string]account{}, usernames: map[string]string{}, sessions: map[[32]byte]string{}, invitations: map[string]invitation{}, contacts: map[string]map[string]contact{}, blocked: map[string]map[string]bool{}, limits: map[string][]time.Time{}}
}
func (s *Server) Sweep() { s.queue.Sweep() }

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		respond(w, 200, map[string]string{"status": "development-only"})
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) { fail(w, 503, "security_integration_incomplete") })
	mux.HandleFunc("POST /v1/accounts", s.register)
	mux.HandleFunc("DELETE /v1/account", s.auth(s.deleteAccount))
	mux.HandleFunc("GET /v1/users/{username}", s.auth(s.lookup))
	mux.HandleFunc("POST /v1/invitations", s.auth(s.invite))
	mux.HandleFunc("GET /v1/invitations", s.auth(s.listInvitations))
	mux.HandleFunc("POST /v1/invitations/{id}/accept", s.auth(s.accept))
	mux.HandleFunc("GET /v1/contacts", s.auth(s.listContacts))
	mux.HandleFunc("POST /v1/blocks/{id}", s.auth(s.block))
	mux.HandleFunc("POST /v1/envelopes", s.submit)
	mux.HandleFunc("GET /v1/envelopes/{id}/status", s.status)
	mux.HandleFunc("GET /v1/queue", s.auth(s.fetch))
	mux.HandleFunc("DELETE /v1/queue/{id}", s.auth(s.ack))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		mux.ServeHTTP(w, r)
	})
}
func respond(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func fail(w http.ResponseWriter, status int, code string) {
	respond(w, status, map[string]string{"error": code})
}
func decode(w http.ResponseWriter, r *http.Request, value any) bool {
	if r.Header.Get("Content-Type") != "application/json" {
		fail(w, 415, "json_required")
		return false
	}
	reader := http.MaxBytesReader(w, r.Body, 48*1024)
	decoder := json.NewDecoder(reader)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		fail(w, 400, "invalid_request")
		return false
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		fail(w, 400, "invalid_request")
		return false
	}
	return true
}
func (s *Server) auth(next func(http.ResponseWriter, *http.Request, string)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodDelete && r.URL.Path == "/v1/account" {
			s.identityLifetime.Lock()
			defer s.identityLifetime.Unlock()
		} else {
			s.identityLifetime.RLock()
			defer s.identityLifetime.RUnlock()
		}
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			fail(w, 401, "unauthorized")
			return
		}
		hash := sha256.Sum256([]byte(strings.TrimPrefix(header, "Bearer ")))
		s.mu.Lock()
		id, ok := s.sessions[hash]
		s.mu.Unlock()
		if !ok {
			fail(w, 401, "unauthorized")
			return
		}
		next(w, r, id)
	}
}

var usernamePattern = regexp.MustCompile(`^[a-z0-9_]{3,24}$`)

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
	}
	if !decode(w, r, &body) {
		return
	}
	if !usernamePattern.MatchString(body.Username) {
		fail(w, 400, "invalid_username")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.accounts) >= 100 {
		fail(w, 429, "beta_capacity")
		return
	}
	if _, exists := s.usernames[body.Username]; exists {
		fail(w, 409, "username_unavailable")
		return
	}
	id, token := relay.RandomToken(), relay.RandomToken()
	hash := sha256.Sum256([]byte(token))
	s.accounts[id] = account{id, body.Username, hash}
	s.sessions[hash] = id
	s.usernames[body.Username] = id
	s.contacts[id] = map[string]contact{}
	s.blocked[id] = map[string]bool{}
	respond(w, 201, map[string]string{"accountId": id, "authToken": token, "username": body.Username})
}

// Per-account development throttles are deliberately not represented as
// production anonymous admission or distributed abuse prevention.
func (s *Server) allow(id string) bool {
	cutoff := s.now().Add(-time.Minute)
	list := s.limits[id][:0]
	for _, t := range s.limits[id] {
		if t.After(cutoff) {
			list = append(list, t)
		}
	}
	if len(list) >= 30 {
		s.limits[id] = list
		return false
	}
	s.limits[id] = append(list, s.now())
	return true
}
func (s *Server) lookup(w http.ResponseWriter, r *http.Request, id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.allow(id) {
		fail(w, 429, "rate_limited")
		return
	}
	peer, ok := s.usernames[r.PathValue("username")]
	if !ok || s.blocked[peer][id] {
		fail(w, 404, "not_found")
		return
	}
	respond(w, 200, map[string]string{"accountId": peer, "username": r.PathValue("username")})
}
func (s *Server) invite(w http.ResponseWriter, r *http.Request, id string) {
	var body struct {
		Recipient string `json:"recipient"`
	}
	if !decode(w, r, &body) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.allow(id) {
		fail(w, 429, "rate_limited")
		return
	}
	if _, ok := s.accounts[body.Recipient]; !ok || body.Recipient == id || s.blocked[body.Recipient][id] || s.blocked[id][body.Recipient] {
		fail(w, 400, "invalid_recipient")
		return
	}
	if _, ok := s.contacts[id][body.Recipient]; ok {
		fail(w, 409, "already_connected")
		return
	}
	for key, v := range s.invitations {
		if !s.now().Before(v.ExpiresAt) {
			delete(s.invitations, key)
		} else if v.From == id && v.To == body.Recipient {
			respond(w, 200, map[string]string{"id": v.ID})
			return
		}
	}
	if len(s.invitations) >= 1000 {
		fail(w, 429, "capacity")
		return
	}
	inv := invitation{relay.RandomToken(), id, body.Recipient, s.now().Add(24 * time.Hour)}
	s.invitations[inv.ID] = inv
	respond(w, 201, map[string]string{"id": inv.ID})
}
func (s *Server) listInvitations(w http.ResponseWriter, r *http.Request, id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	result := []map[string]string{}
	for key, v := range s.invitations {
		if !s.now().Before(v.ExpiresAt) {
			delete(s.invitations, key)
		} else if v.To == id {
			result = append(result, map[string]string{"id": v.ID, "from": v.From, "username": s.accounts[v.From].Username})
		}
	}
	respond(w, 200, result)
}
func (s *Server) accept(w http.ResponseWriter, r *http.Request, id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	inv, ok := s.invitations[r.PathValue("id")]
	if !ok || inv.To != id || !s.now().Before(inv.ExpiresAt) {
		fail(w, 404, "not_found")
		return
	}
	if s.blocked[id][inv.From] || s.blocked[inv.From][id] {
		fail(w, 403, "blocked")
		return
	}
	// Opposite-direction pending invitations must not mint replacement tokens.
	if _, exists := s.contacts[id][inv.From]; !exists {
		s.contacts[inv.From][id] = contact{id, s.accounts[id].Username, s.queue.Grant(id)}
		s.contacts[id][inv.From] = contact{inv.From, s.accounts[inv.From].Username, s.queue.Grant(inv.From)}
	}
	for key, v := range s.invitations {
		if (v.From == id && v.To == inv.From) || (v.From == inv.From && v.To == id) {
			delete(s.invitations, key)
		}
	}
	respond(w, 200, map[string]string{"status": "accepted"})
}
func (s *Server) listContacts(w http.ResponseWriter, r *http.Request, id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	result := []contact{}
	for _, c := range s.contacts[id] {
		result = append(result, c)
	}
	respond(w, 200, result)
}
func (s *Server) block(w http.ResponseWriter, r *http.Request, id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	peer := r.PathValue("id")
	if _, ok := s.accounts[peer]; !ok || peer == id {
		fail(w, 404, "not_found")
		return
	}
	s.blocked[id][peer] = true
	s.disconnect(id, peer)
	for key, v := range s.invitations {
		if (v.From == id && v.To == peer) || (v.From == peer && v.To == id) {
			delete(s.invitations, key)
		}
	}
	respond(w, 200, map[string]string{"status": "blocked"})
}
func (s *Server) disconnect(a, b string) {
	if c, ok := s.contacts[a][b]; ok {
		s.queue.Revoke(c.Token)
		delete(s.contacts[a], b)
	}
	if c, ok := s.contacts[b][a]; ok {
		s.queue.Revoke(c.Token)
		delete(s.contacts[b], a)
	}
}
func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request, id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	a := s.accounts[id]
	for peer := range s.contacts[id] {
		s.disconnect(id, peer)
	}
	for key, v := range s.invitations {
		if v.From == id || v.To == id {
			delete(s.invitations, key)
		}
	}
	for _, peers := range s.blocked {
		delete(peers, id)
	}
	delete(s.accounts, id)
	delete(s.sessions, a.auth)
	delete(s.usernames, a.Username)
	delete(s.contacts, id)
	delete(s.blocked, id)
	delete(s.limits, id)
	s.queue.DeleteRecipient(id)
	w.WriteHeader(204)
}
func submissionToken(w http.ResponseWriter, r *http.Request) (string, bool) {
	if r.Header.Get("Authorization") != "" || r.Header.Get("Cookie") != "" {
		fail(w, 400, "sender_auth_forbidden")
		return "", false
	}
	token := r.Header.Get("Delivery-Token")
	if len(token) != 64 {
		fail(w, 401, "unauthorized")
		return "", false
	}
	return token, true
}
func (s *Server) submit(w http.ResponseWriter, r *http.Request) {
	token, ok := submissionToken(w, r)
	if !ok {
		return
	}
	var body struct {
		ID         string `json:"id"`
		Ciphertext []byte `json:"ciphertext"`
	}
	if !decode(w, r, &body) {
		return
	}
	receipt, err := s.queue.Submit(token, body.ID, body.Ciphertext)
	if err != nil {
		queueError(w, err)
		return
	}
	respond(w, 202, receipt)
}
func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	token, ok := submissionToken(w, r)
	if !ok {
		return
	}
	receipt, err := s.queue.Status(token, r.PathValue("id"))
	if err != nil {
		queueError(w, err)
		return
	}
	respond(w, 200, receipt)
}
func (s *Server) fetch(w http.ResponseWriter, r *http.Request, id string) {
	respond(w, 200, s.queue.Fetch(id))
}
func (s *Server) ack(w http.ResponseWriter, r *http.Request, id string) {
	if err := s.queue.Ack(id, r.PathValue("id")); err != nil {
		queueError(w, err)
		return
	}
	w.WriteHeader(204)
}
func queueError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, relay.ErrUnauthorized):
		fail(w, 401, "unauthorized")
	case errors.Is(err, relay.ErrConflict):
		fail(w, 409, "idempotency_conflict")
	case errors.Is(err, relay.ErrCapacity):
		fail(w, 429, "capacity")
	case errors.Is(err, relay.ErrNotFound):
		fail(w, 404, "not_found")
	default:
		fail(w, 400, "invalid_envelope")
	}
}
