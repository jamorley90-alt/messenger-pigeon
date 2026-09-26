# TestFlight handoff

No Apple credentials are stored in this repository. The development bundle ID is a placeholder and must never be submitted as the real app identity.

## Inputs needed from the owner

- The public GitHub repository has been created at `jamorley90-alt/messenger-pigeon`; CI must pass before distribution.
- Apple Developer Team ID and the chosen reverse-DNS bundle identifier.
- App Store Connect app record and signing configuration, supplied through protected CI secrets when the release target is ready. Never put a private key, certificate password or Apple login into chat or a tracked file.
- Two iPhones with iOS 26 or later and their TestFlight tester addresses.
- Hosting account/domain and approval of an exact quote before any paid service is created.
- A second developer for sensitive-code review and an independently operated transparency auditor.

## First Mac build

The source is published. Run `Development checks` after source changes, and manually run `Native libsignal feasibility probe` when the pinned protocol integration changes. Inspect the Xcode result bundles and retain reviewed evidence. The app workflow uses ad-hoc simulator signing to exercise Keychain access; neither workflow produces a device-signed archive or uploads to TestFlight.

`testFileHasCompleteProtectionOnDevice` is explicitly skipped in the simulator. Run it on both physical iPhones, and also verify that protected files and Keychain keys are unavailable while locked. A green simulator build does not satisfy this release check.

## Release after the gates pass

1. Select the real bundle ID/team and complete the app icon, privacy/support information and beta review instructions.
2. Add notification entitlement and APNs configuration only when generic notifications are implemented and tested.
3. Complete App Store Connect's encryption questionnaire for the actual third-party cryptography. Do not set the non-exempt-encryption flag to false merely to avoid review.
4. Run `node scripts/verify-release.mjs`; confirm evidence for every gate against the exact source revision.
5. Archive and sign using the Apple-supported Xcode/SDK version at submission time. Review the binary and metadata, then upload using protected signing credentials.
6. Test internally on both phones. Submit to external beta review with steps for creating two accounts, accepting an invitation and exchanging messages. Keep the backend available during review.
7. Invite the small external group after approval. TestFlight builds expire after 90 days; ship a new tested build before expiry if the beta continues.

## Physical-device matrix

Test clean install, denied notifications, device lock, app backgrounding, force-quit before/after opening, reboot, offline use, clock rollback, service outage, lost acceptance response, duplicate fetch/ack, opening at 23h59m59s, identity change, blocking and account deletion. Inspect backup behaviour, app-switcher images, accessibility labels, notification history, backend logs and crash reports for prohibited content. Compare valid/invalid pins, TLS versions, hybrid negotiation, altered ciphertext, invalid proofs and substituted identity keys.

## Expected demonstration

Phone A invites B; B accepts. Compare safety numbers. A sends a text; A's copy counts down independently. B gets a generic notification, explicitly opens the card and sees its own countdown. Background and reopen B without resetting it. Repeat in reverse, then demonstrate blocking. No saved message history should remain.
