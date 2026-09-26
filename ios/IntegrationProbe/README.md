# Native cryptography integration probe

This target uses real libsignal APIs, isolated from the fictional UI preview. It is a simulator feasibility test, not a live messaging implementation or proof of complete protocol enforcement.

The library is pinned to 0.103.1 at commit `e8cc2dddd578859b4a029c9c94670b24ce2b616a`. Its published iOS native archive SHA-256 is pinned in the Podfile. Upstream source and CocoaPods/native archive verification remain necessary during the first Mac build.

On macOS:

```sh
xcodegen generate
bundle install
bundle exec pod install
xcodebuild test -workspace SignalIntegrationProbe.xcworkspace -scheme SignalIntegrationProbe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

The CI runner selects an available iPhone simulator instead of relying on the example device name. Commit the generated Podfile.lock and Gemfile.lock after the first successful resolution; release remains blocked until transitive tools are locked and the simulator/device results are recorded.

The test stores are upstream in-memory stores. They must never become the app's production storage or identity-verification policy. The probe tests initial hybrid session exchange, reply, tamper rejection, replay rejection and sealed-sender wrapping/certificate validation. It does not establish persistent ratchet crash safety, all Triple Ratchet downgrade paths, key transparency, or device-level security.
