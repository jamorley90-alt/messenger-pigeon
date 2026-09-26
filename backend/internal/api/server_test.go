package api

import (
	"bytes"
	"encoding/json"
	"messengerpigeon/backend/internal/relay"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

type client struct{ ID, Auth string }

func request(h http.Handler, method, path string, body any, auth, delivery string) *httptest.ResponseRecorder {
	var b bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&b).Encode(body)
	}
	r := httptest.NewRequest(method, path, &b)
	r.Header.Set("Content-Type", "application/json")
	if auth != "" {
		r.Header.Set("Authorization", "Bearer "+auth)
	}
	if delivery != "" {
		r.Header.Set("Delivery-Token", delivery)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}
func register(t *testing.T, h http.Handler, name string) client {
	t.Helper()
	r := request(h, "POST", "/v1/accounts", map[string]string{"username": name}, "", "")
	if r.Code != 201 {
		t.Fatal(r.Code, r.Body.String())
	}
	var value map[string]string
	_ = json.Unmarshal(r.Body.Bytes(), &value)
	return client{value["accountId"], value["authToken"]}
}
func connect(t *testing.T, h http.Handler, a, b client) string {
	t.Helper()
	r := request(h, "POST", "/v1/invitations", map[string]string{"recipient": b.ID}, a.Auth, "")
	if r.Code != 201 {
		t.Fatal(r.Code)
	}
	var v map[string]string
	_ = json.Unmarshal(r.Body.Bytes(), &v)
	r = request(h, "POST", "/v1/invitations/"+v["id"]+"/accept", nil, b.Auth, "")
	if r.Code != 200 {
		t.Fatal(r.Code)
	}
	r = request(h, "GET", "/v1/contacts", nil, a.Auth, "")
	var contacts []contact
	_ = json.Unmarshal(r.Body.Bytes(), &contacts)
	if len(contacts) != 1 {
		t.Fatal("missing contact")
	}
	return contacts[0].Token
}
func TestFullConsentDeliveryBlockingFlow(t *testing.T) {
	h := New(time.Now).Handler()
	alice := register(t, h, "alice")
	bob := register(t, h, "bob")
	eve := register(t, h, "eve")
	payload := map[string]any{"id": relay.RandomToken(), "ciphertext": []byte{1, 2, 3}}
	if r := request(h, "POST", "/v1/envelopes", payload, "", relay.RandomToken()); r.Code != 401 {
		t.Fatal("accepted without consent", r.Code)
	}
	token := connect(t, h, alice, bob)
	if r := request(h, "POST", "/v1/envelopes", payload, alice.Auth, token); r.Code != 400 {
		t.Fatal("linked sender authentication", r.Code)
	}
	if r := request(h, "POST", "/v1/envelopes", payload, "", token); r.Code != 202 {
		t.Fatal(r.Code, r.Body.String())
	}
	if r := request(h, "GET", "/v1/queue", nil, eve.Auth, ""); r.Body.String() != "[]\n" {
		t.Fatal("leaked message")
	}
	if r := request(h, "GET", "/v1/queue", nil, bob.Auth, ""); !bytes.Contains(r.Body.Bytes(), []byte("AQID")) {
		t.Fatal("not delivered")
	}
	if r := request(h, "POST", "/v1/blocks/"+alice.ID, nil, bob.Auth, ""); r.Code != 200 {
		t.Fatal(r.Code)
	}
	if r := request(h, "POST", "/v1/envelopes", payload, "", token); r.Code != 401 {
		t.Fatal("revoked token accepted")
	}
	if r := request(h, "GET", "/v1/queue", nil, bob.Auth, ""); r.Body.String() != "[]\n" {
		t.Fatal("blocked content retained")
	}
	if r := request(h, "POST", "/v1/invitations", map[string]string{"recipient": bob.ID}, alice.Auth, ""); r.Code != 400 {
		t.Fatal("blocked invitation")
	}
}
func TestDeleteRevokesAuthAndRelationships(t *testing.T) {
	h := New(time.Now).Handler()
	a := register(t, h, "alice")
	b := register(t, h, "bob")
	token := connect(t, h, a, b)
	if r := request(h, "DELETE", "/v1/account", nil, b.Auth, ""); r.Code != 204 {
		t.Fatal(r.Code)
	}
	if r := request(h, "GET", "/v1/contacts", nil, b.Auth, ""); r.Code != 401 {
		t.Fatal("deleted token works")
	}
	if r := request(h, "GET", "/v1/contacts", nil, a.Auth, ""); r.Body.String() != "[]\n" {
		t.Fatal("retained contact")
	}
	if r := request(h, "POST", "/v1/envelopes", map[string]any{"id": relay.RandomToken(), "ciphertext": []byte{1}}, "", token); r.Code != 401 {
		t.Fatal("deleted delivery token works")
	}
}
func TestInvitationCannotBeAcceptedByThirdParty(t *testing.T) {
	h := New(time.Now).Handler()
	a := register(t, h, "alice")
	b := register(t, h, "bob")
	c := register(t, h, "charlie")
	r := request(h, "POST", "/v1/invitations", map[string]string{"recipient": b.ID}, a.Auth, "")
	var inv map[string]string
	_ = json.Unmarshal(r.Body.Bytes(), &inv)
	if r = request(h, "POST", "/v1/invitations/"+inv["id"]+"/accept", nil, c.Auth, ""); r.Code != 404 {
		t.Fatal(r.Code)
	}
}
func TestStrictJSONAndNoCache(t *testing.T) {
	h := New(time.Now).Handler()
	for _, body := range []any{map[string]any{"username": "alice", "message": "hidden text"}, map[string]any{"username": "ALICE"}} {
		r := request(h, "POST", "/v1/accounts", body, "", "")
		if r.Code != 400 {
			t.Fatal(r.Code)
		}
		if r.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("cacheable")
		}
	}
	r := httptest.NewRequest("POST", "/v1/accounts", bytes.NewBufferString(`{"username":"alice"} {}`))
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 400 {
		t.Fatal("trailing JSON accepted")
	}
}
func TestLookupIsExactAndRateLimited(t *testing.T) {
	h := New(time.Now).Handler()
	a := register(t, h, "alice")
	_ = register(t, h, "bobby")
	if r := request(h, "GET", "/v1/users/bob", nil, a.Auth, ""); r.Code != 404 {
		t.Fatal("prefix lookup")
	}
	for range 29 {
		request(h, "GET", "/v1/users/bobby", nil, a.Auth, "")
	}
	if r := request(h, "GET", "/v1/users/bobby", nil, a.Auth, ""); r.Code != 429 {
		t.Fatal("not limited", r.Code)
	}
}
func TestReadinessNeverClaimsProduction(t *testing.T) {
	r := request(New(time.Now).Handler(), "GET", "/readyz", nil, "", "")
	if r.Code != 503 {
		t.Fatal("release gate bypass")
	}
}
