# Release gates and current implementation status

The requested end state is a real, private, two-phone TestFlight demo. It has **not** been reached. This working tree contains local development components and a native integration probe. No app has been compiled with Xcode, uploaded, signed or security-reviewed here.

## Verified locally

- Go API tests: account isolation, recipient-only consent, exact username lookup, rate limiting, blocking, deletion and strict JSON.
- Relay tests: original acceptance on retry, digest conflict detection, acknowledgement deduplication, exact expiry, cross-account rejection, queue capacity and concurrent retry.
- In-memory TLS handshakes: TLS 1.3 + X25519MLKEM768 succeeds; classical-only and TLS 1.2 clients fail.
- Release-manifest checker rejects incomplete gates. It is a workflow guard, not a security attestation.

## Written but awaiting macOS/device execution

- Swift lifecycle tests for explicit opening, both expiry policies, replay, process restoration, clock rollback and UTF-8 limits.
- SwiftUI interaction preview, native Keychain/AES-GCM unread vault, backup exclusion and consume-before-render tests.
- Actual libsignal session, tamper, replay and sealed-sender probe tests, pinned by source commit and native archive hash.
- Hosted macOS workflows with no signing secrets and no upload action.

## Feasibility findings that block the live beta

1. **Native build:** this Windows machine has no Xcode or Swift compiler. The public repository `jamorley90-alt/messenger-pigeon` has been created for macOS workflows. Two physical iPhones must then run the integration tests.
2. **Key transparency:** at libsignal commit `e8cc2dddd578859b4a029c9c94670b24ce2b616a`, `swift/Sources/LibSignalClient/KeyTransparency.swift` constructs its client internally from `UnauthenticatedChatConnection`, `TokioAsyncContext` and `Net.Environment`. It is not a public standalone proof-verifier interface for an arbitrary endpoint. Next work must expose the maintained Rust verification implementation through a small reviewed native bridge and adapt the standalone server; do not implement a new proof system or connect this app to Signal's service. The independently operated auditor/checkpoint relationship is also not provisioned.
3. **Protocol:** tracing `KEMKeyPair.generate()` through `signal_kyber_key_pair_generate` to `rust/bridge/shared/src/protocol.rs` shows `KYBER_KEY_TYPE = kem::KeyType::Kyber1024`. The source has a separate feature-gated ML-KEM-1024 type. Do not label this Swift default as final FIPS ML-KEM-1024. The ratchet initialisation specifies SPQR V1 as its minimum. Native runtime tests and all downgrade paths still need validation. Keep maintained defaults unchanged, as agreed.
4. **Storage/transport integration:** the unread vault is not wired to transactional durable libsignal session/replay storage. The account API remains memory-only. Production PostgreSQL, certificate issuance, APNs, iPhone public-key pinning, trusted-time reconciliation and deployment have not been implemented.
5. **Distribution:** Apple Team ID, actual bundle ID, public repository, signing assets, beta metadata, icon and encryption declaration are not available. An approved paid-hosting quote is needed if free infrastructure cannot meet the TLS and auditor requirements.

Independent specialist assessment remains a production gate, deferred until after the private demo by the user. A second developer must still review sensitive implementation changes before the private beta; no such review has occurred.

## Exact continuation order

1. Run both Mac workflows, correct compiler/integration findings and commit generated dependency locks.
2. Expose upstream transparency verification with test vectors, self/contact monitoring and independently authenticated checkpoints; fail closed on substitution and inconsistent views.
3. Implement the device identity/prekey lifecycle and transactional protocol store. Connect real sealed messages to the relay with authenticated application fields, padding and replay handling. Remove all test-only trust stores from the live target.
4. Add PostgreSQL account/device persistence, encrypted ephemeral routing storage, anonymous admission limits, consent-token rotation, APNs and HTTPS deployment. Verify key pin rotation and hybrid negotiation on the actual iPhones.
5. Complete the physical-device matrix, second-person review, licence/source distribution and signed TestFlight submission.

Do not enable the live UI or change readiness entries to passed based solely on the offline preview or Go unit tests. If these gates cannot be satisfied by the target date, revise the date rather than weaken the selected security requirements.
