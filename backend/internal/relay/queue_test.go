package relay

import (
	"bytes"
	"errors"
	"sync"
	"testing"
	"time"
)

func fixture() (*Queue, *time.Time, string) {
	now := time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)
	q := New(100, func() time.Time { return now })
	return q, &now, q.Grant("bob")
}
func TestAcceptanceRetryAndAcknowledgement(t *testing.T) {
	q, now, token := fixture()
	id := RandomToken()
	body := []byte("opaque fixture, not encryption")
	first, err := q.Submit(token, id, body)
	if err != nil {
		t.Fatal(err)
	}
	*now = now.Add(30 * time.Second)
	again, err := q.Submit(token, id, body)
	if err != nil || first != again {
		t.Fatal("retry changed acceptance", err)
	}
	if len(q.Fetch("alice")) != 0 {
		t.Fatal("cross-account fetch")
	}
	if err = q.Ack("alice", id); !errors.Is(err, ErrUnauthorized) {
		t.Fatal(err)
	}
	if err = q.Ack("bob", id); err != nil {
		t.Fatal(err)
	}
	if err = q.Ack("bob", id); err != nil {
		t.Fatal("duplicate ack", err)
	}
	_, err = q.Submit(token, id, body)
	if err != nil || len(q.Fetch("bob")) != 0 {
		t.Fatal("acknowledged content resurrected", err)
	}
	status, err := q.Status(token, id)
	if err != nil || status != first {
		t.Fatal("lost receipt", err)
	}
}
func TestExpiryAtExactDeadlineWithoutSweep(t *testing.T) {
	q, now, token := fixture()
	id := RandomToken()
	r, _ := q.Submit(token, id, []byte{1})
	*now = r.ExpiresAt
	if len(q.Fetch("bob")) != 0 {
		t.Fatal("expired delivery")
	}
	if _, err := q.Status(token, id); !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
}
func TestRevokeDropsPendingContentAndRejectsToken(t *testing.T) {
	q, _, token := fixture()
	_, _ = q.Submit(token, RandomToken(), []byte{1})
	q.Revoke(token)
	if len(q.Fetch("bob")) != 0 {
		t.Fatal("blocked content retained")
	}
	if _, err := q.Submit(token, RandomToken(), []byte{1}); !errors.Is(err, ErrUnauthorized) {
		t.Fatal(err)
	}
}
func TestInputAndOutputCannotMutateStoredCiphertext(t *testing.T) {
	q, _, token := fixture()
	body := []byte{1, 2, 3}
	_, _ = q.Submit(token, RandomToken(), body)
	body[0] = 9
	fetched := q.Fetch("bob")
	fetched[0].Ciphertext[0] = 8
	if !bytes.Equal(q.Fetch("bob")[0].Ciphertext, []byte{1, 2, 3}) {
		t.Fatal("aliased ciphertext")
	}
}
func TestConflictsAndInvalidEnvelopes(t *testing.T) {
	q, _, token := fixture()
	id := RandomToken()
	_, _ = q.Submit(token, id, []byte{1})
	if _, err := q.Submit(token, id, []byte{2}); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	other := q.Grant("charlie")
	if _, err := q.Submit(other, id, []byte{1}); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	for _, body := range [][]byte{nil, make([]byte, MaxEnvelopeBytes+1)} {
		if _, err := q.Submit(token, RandomToken(), body); !errors.Is(err, ErrInvalid) {
			t.Fatal(err)
		}
	}
	if _, err := q.Submit(token, "bad-id", []byte{1}); !errors.Is(err, ErrInvalid) {
		t.Fatal(err)
	}
}
func TestCapacityCountsDeduplicationAndExpires(t *testing.T) {
	now := time.Now()
	q := New(1, func() time.Time { return now })
	token := q.Grant("bob")
	id := RandomToken()
	_, _ = q.Submit(token, id, []byte{1})
	_ = q.Ack("bob", id)
	if _, err := q.Submit(token, RandomToken(), []byte{1}); !errors.Is(err, ErrCapacity) {
		t.Fatal(err)
	}
	now = now.Add(Lifetime)
	if _, err := q.Submit(token, RandomToken(), []byte{1}); err != nil {
		t.Fatal(err)
	}
}
func TestConcurrentRetryAcceptsExactlyOnce(t *testing.T) {
	q, _, token := fixture()
	id := RandomToken()
	var wg sync.WaitGroup
	for range 50 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := q.Submit(token, id, []byte{1}); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if len(q.Fetch("bob")) != 1 {
		t.Fatal("duplicate delivery")
	}
}
func TestDeleteRecipientRevokesTokens(t *testing.T) {
	q, _, token := fixture()
	_, _ = q.Submit(token, RandomToken(), []byte{1})
	q.DeleteRecipient("bob")
	if len(q.Fetch("bob")) != 0 {
		t.Fatal("retained deleted account content")
	}
	if _, err := q.Status(token, RandomToken()); !errors.Is(err, ErrUnauthorized) {
		t.Fatal(err)
	}
}
