# Development API

The current HTTP API is loopback-only and memory-only. It routes opaque bytes; it does not prove that submitted bytes are encrypted. No production client is connected. `/readyz` deliberately returns 503.

JSON bodies use `Content-Type: application/json`, reject unknown fields and extra JSON values, and have a 48 KiB body limit. All responses are `Cache-Control: no-store`. IDs and bearer credentials are random 32-byte hexadecimal values. Authentication tokens are hashed in memory. There is one development session per account.

| Method and path | Authentication | Input or result |
| --- | --- | --- |
| POST /v1/accounts | None; loopback only | `{username}` → `{accountId,authToken,username}` |
| DELETE /v1/account | Account bearer | Revoke account, contacts, tokens, invitations and queue |
| GET /v1/users/{username} | Account bearer | Exact match only; no prefix search |
| POST /v1/invitations | Account bearer | `{recipient}` → `{id}`; no message text |
| GET /v1/invitations | Account bearer | Unexpired incoming invitations |
| POST /v1/invitations/{id}/accept | Recipient bearer | Establish consent and per-direction delivery credentials |
| GET /v1/contacts | Account bearer | `{peer,username,deliveryToken}` entries |
| POST /v1/blocks/{id} | Account bearer | Revoke both delivery directions and pending invitations |
| POST /v1/envelopes | Delivery-Token header only | `{id,ciphertext}` where ciphertext is base64; return acceptance receipt |
| GET /v1/envelopes/{id}/status | Delivery-Token header only | Original receipt; never a sender-authenticated lookup |
| GET /v1/queue | Recipient bearer | Up to 100 unacknowledged envelopes |
| DELETE /v1/queue/{id} | Recipient bearer | Delete ciphertext, retain bounded deduplication metadata |

Submission rejects account Authorization and Cookie headers. The queue stores recipient routing, a token hash, ciphertext digest and receipt metadata, but no sender account field. The development contact service still knows contact relationships and issued credentials. This separation is not a claim of operator anonymity or unlinkability.

Receipts use RFC3339 timestamps: `{id,acceptedAt,expiresAt}`. Expiry is exactly acceptance + 24 hours and is enforced on fetch/status/ack, independently of the sweep. IDs are idempotent within this delivery window: identical retry → original receipt; different body/token → 409. After the window, clients must never treat an unknown status as permission to resend an old message. Persistent client replay state and protocol checks remain necessary.

Queue capacity is 2,000 records including acknowledged deduplication records; maximum envelope size is 32 KiB. Development account capacity is 100; username lookups and invitations share a 30/minute per-account limit. These are test safeguards, not sufficient internet-facing abuse prevention.

Future production endpoints for prekeys, transparency, authenticated service time, device replacement and push registration are **not implemented**. Do not treat a generic HTTP success as cryptographic validation.

