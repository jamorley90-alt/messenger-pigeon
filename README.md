# Messenger Pigeon

Native iPhone messaging project based on the supplied technical design. This repository is an implementation in progress, **not a security-reviewed messenger or a TestFlight release**.

## What runs now

- A SwiftUI iPhone interface with an explicitly labelled, offline interaction preview.
- A platform-independent Swift lifecycle package with deterministic expiry and replay tests.
- Authenticated application-payload validation and bucket padding, ready for the native protocol adapter.
- A Go development API for accounts, contact consent, blocking and an ephemeral opaque-envelope relay, with automated adversarial tests.
- A macOS CI workflow that generates the Xcode project, runs Swift tests and compiles the simulator app.
- A pinned libsignal integration probe; release gates prevent publishing incomplete security integrations.

The preview uses fictional messages and never connects to the relay. The app's live mode is intentionally unavailable until the gates in `docs/RELEASE-GATES.md` pass. The development API must not be exposed publicly: its account store and abuse limits are process-local, and it has no production transport or cryptographic attestation.

## Backend development

Install Go 1.27.1, then:

```sh
cd backend
go test ./...
go run ./cmd/relay -dev
```

The server binds only to `127.0.0.1:8080`; non-development startup fails closed. Restarting it loses accounts, invitations and queued envelopes. Requests and response bodies are never logged. `docs/API.md` describes the implemented development endpoints.

## iPhone development

On a Mac with Xcode supporting iOS 26, install XcodeGen 2.44.1, run `xcodegen generate` from `ios/`, and open `MessengerPigeon.xcodeproj`. The unsigned simulator target needs no Apple credentials or external Swift packages. The app requires iOS 26+. Run the pure lifecycle tests using `swift test --package-path packages/PigeonCore`.

The separate `ios/IntegrationProbe` target compiles and exercises the pinned libsignal API via CocoaPods. It does not enable live messaging. See its README for instructions and native build requirements.

## From Windows to TestFlight

The public source repository is https://github.com/jamorley90-alt/messenger-pigeon. Its macOS CI workflow builds the project without requiring a local Mac. No paid service or Apple app record has been created. See `docs/TESTFLIGHT.md` for the signing and distribution dependencies. Do not upload the current interaction preview as the promised real-messaging demo.

This project's source is licensed under AGPL-3.0-only; see `LICENSE`. The pinned upstream library retains its own notices. Licence compatibility, a complete source distribution and all third-party notices remain release checks; this README is not a legal compatibility determination.
