# Release gates and current implementation status

The requested end state is a real, private, two-phone TestFlight demo. It has **not** been reached. This working tree contains development components, a SwiftUI interaction preview and a native integration probe. Hosted Xcode builds have compiled the source and the real cryptography probe has passed. No device-signed app has been uploaded to TestFlight or independently security-reviewed.

## Verified locally

- Go API tests: account isolation, recipient-only consent, exact username lookup, rate limiting, blocking, deletion and strict JSON.
- Relay tests: original acceptance on retry, digest conflict detection, acknowledgement deduplication, exact expiry, cross-account rejection, queue capacity and concurrent retry.
- In-memory TLS handshakes: TLS 1.3 + X25519MLKEM768 succeeds; classical-only and TLS 1.2 clients fail.
- Release-manifest checker rejects incomplete gates. It is a workflow guard, not a security attestation.

## Verified on hosted macOS

- All 13 Swift lifecycle and application-envelope tests pass, covering opening, expiry, replay, process restoration, clock rollback, payload validation, padding and UTF-8 limits.
- All four actual libsignal session, tamper, replay and sealed-sender probe tests pass, pinned by source commit and native archive hash. Evidence: https://github.com/jamorley90-alt/messenger-pigeon/actions/runs/36242063699 (source `7e76514`).
- Backend race tests and release-checker tests also pass in GitHub Actions.
- The SwiftUI app builds and its interface test passes. Three unread-vault tests pass with real simulator Keychain access, covering consume-once deletion, expiry and backup exclusion. The hardware file-protection test is explicitly skipped. Evidence: https://github.com/jamorley90-alt/messenger-pigeon/actions/runs/36243082355 (source `39f0684`). Its conversation screenshot was visually reviewed; physical-device verification remains pending.
- Across the two workflows: 43 passing tests (17 Go, 5 release checker, 13 Swift core, 4 libsignal, 3 vault, 1 UI) and 1 hardware-only skipped test. Passing these component tests does not establish end-to-end live-messaging security.

## Feasibility findings that block the live beta

1. **Physical devices:** free hosted macOS workflows provide Xcode builds for this Windows workspace. Two physical iPhones must still run the integration tests, including locked-device file and Keychain protection. The simulator file-protection test is explicitly skipped and cannot be counted as device evidence.
2. **Key transparency:** at libsignal commit `e8cc2dddd578859b4a029c9c94670b24ce2b616a`, `swift/Sources/LibSignalClient/KeyTransparency.swift` constructs its client internally from `UnauthenticatedChatConnection`, `TokioAsyncContext` and `Net.Environment`. It is not a public standalone proof-verifier interface for an arbitrary endpoint. Next work must expose the maintained Rust verification implementation through a small reviewed native bridge and adapt the standalone server; do not implement a new proof system or connect this app to Signal's service. The independently operated auditor/checkpoint relationship is also not provisioned.
3. **Protocol:** tracing `KEMKeyPair.generate()` through `signal_kyber_key_pair_generate` to `rust/bridge/shared/src/protocol.rs` shows `KYBER_KEY_TYPE = kem::KeyType::Kyber1024`. The source has a separate feature-gated ML-KEM-1024 type. Do not label this Swift default as final FIPS ML-KEM-1024. The ratchet initialisation specifies SPQR V1 as its minimum. Four native probe tests pass; complete downgrade-path and application integration validation remains pending. Keep maintained defaults unchanged, as agreed.
4. **Storage/transport integration:** the unread vault is not wired to transactional durable libsignal session/replay storage. The account API remains memory-only. Production PostgreSQL, certificate issuance, APNs, iPhone public-key pinning, trusted-time reconciliation and deployment have not been implemented.
5. **Distribution:** Apple Team ID, actual bundle ID, device signing assets, beta metadata, icon and encryption declaration are not available. The public repository and free hosted Mac workflow now exist. An approved paid-hosting quote is needed if free infrastructure cannot meet the TLS and auditor requirements.

Independent specialist assessment remains a production gate, deferred until after the private demo by the user. A second developer must still review sensitive implementation changes before the private beta; no such review has occurred.

## Exact continuation order

1. Retain the passing Mac build/probe evidence and dependency locks, then rerun the affected workflows after integration changes.
2. Expose upstream transparency verification with test vectors, self/contact monitoring and independently authenticated checkpoints; fail closed on substitution and inconsistent views.
3. Implement the device identity/prekey lifecycle and transactional protocol store. Connect real sealed messages to the relay with authenticated application fields, padding and replay handling. Remove all test-only trust stores from the live target.
4. Add PostgreSQL account/device persistence, encrypted ephemeral routing storage, anonymous admission limits, consent-token rotation, APNs and HTTPS deployment. Verify key pin rotation and hybrid negotiation on the actual iPhones.
5. Complete the physical-device matrix, second-person review, licence/source distribution and signed TestFlight submission.

Do not enable the live UI or change readiness entries to passed based solely on the offline preview or Go unit tests. If these gates cannot be satisfied by the target date, revise the date rather than weaken the selected security requirements.
