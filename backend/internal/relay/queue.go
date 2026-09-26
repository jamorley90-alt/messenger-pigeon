// Package relay implements an ephemeral opaque-envelope queue. It never
// decrypts an envelope or claims to validate its end-to-end cryptography.
package relay

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"sync"
	"time"
)

const Lifetime = 24 * time.Hour
const MaxEnvelopeBytes = 32 * 1024

var (
	ErrUnauthorized = errors.New("unauthorized")
	ErrConflict     = errors.New("idempotency conflict")
	ErrInvalid      = errors.New("invalid envelope")
	ErrCapacity     = errors.New("queue capacity reached")
	ErrNotFound     = errors.New("not found")
)

type Envelope struct {
	ID         string    `json:"id"`
	Ciphertext []byte    `json:"ciphertext"`
	AcceptedAt time.Time `json:"acceptedAt"`
	ExpiresAt  time.Time `json:"expiresAt"`
}
type Receipt struct {
	ID         string    `json:"id"`
	AcceptedAt time.Time `json:"acceptedAt"`
	ExpiresAt  time.Time `json:"expiresAt"`
}
type record struct {
	Envelope
	recipient string
	tokenHash [32]byte
	digest    [32]byte
}
type Queue struct {
	mu       sync.Mutex
	now      func() time.Time
	capacity int
	tokens   map[[32]byte]string
	records  map[string]*record
}

func New(capacity int, now func() time.Time) *Queue {
	return &Queue{now: now, capacity: capacity, tokens: make(map[[32]byte]string), records: make(map[string]*record)}
}

func RandomToken() string {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}

// Grant is called only after recipient consent. No sender account is stored in
// this queue; the separate development consent service owns that relationship.
func (q *Queue) Grant(recipient string) string {
	q.mu.Lock()
	defer q.mu.Unlock()
	token := RandomToken()
	q.tokens[sha256.Sum256([]byte(token))] = recipient
	return token
}

func (q *Queue) Revoke(token string) {
	q.mu.Lock()
	defer q.mu.Unlock()
	hash := sha256.Sum256([]byte(token))
	delete(q.tokens, hash)
	for _, r := range q.records {
		if r.tokenHash == hash {
			r.Ciphertext = nil
		}
	}
}

func (q *Queue) DeleteRecipient(recipient string) {
	q.mu.Lock()
	defer q.mu.Unlock()
	for hash, account := range q.tokens {
		if account == recipient {
			delete(q.tokens, hash)
		}
	}
	for id, r := range q.records {
		if r.recipient == recipient {
			delete(q.records, id)
		}
	}
}

func (q *Queue) prune() {
	now := q.now()
	for id, r := range q.records {
		if !now.Before(r.ExpiresAt) {
			delete(q.records, id)
		}
	}
}
func (q *Queue) Sweep() { q.mu.Lock(); defer q.mu.Unlock(); q.prune() }

func (q *Queue) Submit(token, id string, ciphertext []byte) (Receipt, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.prune()
	hash := sha256.Sum256([]byte(token))
	recipient, ok := q.tokens[hash]
	if !ok {
		return Receipt{}, ErrUnauthorized
	}
	if len(id) != 64 || len(ciphertext) == 0 || len(ciphertext) > MaxEnvelopeBytes {
		return Receipt{}, ErrInvalid
	}
	if _, err := hex.DecodeString(id); err != nil {
		return Receipt{}, ErrInvalid
	}
	digest := sha256.Sum256(ciphertext)
	if r, exists := q.records[id]; exists {
		if r.tokenHash != hash || r.digest != digest {
			return Receipt{}, ErrConflict
		}
		return receipt(r), nil
	}
	if len(q.records) >= q.capacity {
		return Receipt{}, ErrCapacity
	}
	now := q.now().UTC()
	r := &record{Envelope: Envelope{ID: id, Ciphertext: append([]byte(nil), ciphertext...), AcceptedAt: now, ExpiresAt: now.Add(Lifetime)}, recipient: recipient, tokenHash: hash, digest: digest}
	q.records[id] = r
	return receipt(r), nil
}
func receipt(r *record) Receipt { return Receipt{r.ID, r.AcceptedAt, r.ExpiresAt} }

func (q *Queue) Status(token, id string) (Receipt, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.prune()
	hash := sha256.Sum256([]byte(token))
	if _, ok := q.tokens[hash]; !ok {
		return Receipt{}, ErrUnauthorized
	}
	r, ok := q.records[id]
	if !ok || r.tokenHash != hash {
		return Receipt{}, ErrNotFound
	}
	return receipt(r), nil
}

func (q *Queue) Fetch(recipient string) []Envelope {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.prune()
	result := make([]Envelope, 0)
	for _, r := range q.records {
		if r.recipient == recipient && r.Ciphertext != nil {
			copy := r.Envelope
			copy.Ciphertext = append([]byte(nil), r.Ciphertext...)
			result = append(result, copy)
			if len(result) == 100 {
				break
			}
		}
	}
	return result
}

func (q *Queue) Ack(recipient, id string) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.prune()
	r, ok := q.records[id]
	if !ok {
		return ErrNotFound
	}
	if r.recipient != recipient {
		return ErrUnauthorized
	}
	// Retain only bounded digest/receipt metadata until the original deadline.
	r.Ciphertext = nil
	return nil
}
