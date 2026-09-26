import LocalAuthentication
import SwiftUI
import PigeonCore

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var preview = false
    @State private var locked = false
    @State private var authenticationError: String?
    @State private var showReadiness = false
    @State private var model = PreviewModel()

    var body: some View {
        ZStack {
            if preview {
                ChatListView(model: model, exit: {
                    model.discardAll(); preview = false; locked = false
                })
            } else {
                welcome
            }
            if scenePhase != .active || locked {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 42)).foregroundStyle(Color.pigeonGreen)
                    Text("Messenger Pigeon").font(.title2.weight(.semibold))
                    if locked && scenePhase == .active {
                        Button("Unlock", action: unlock).buttonStyle(.borderedProminent).controlSize(.large)
                        if let authenticationError { Text(authenticationError).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        Button("Leave preview") { model.discardAll(); preview = false; locked = false }
                    }
                }.padding(32)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.cover(); if preview { locked = true } }
            else { model.tick() }
        }
        .sheet(isPresented: $showReadiness) { ReadinessView() }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack { Image(systemName: "bird.fill"); Text("MESSENGER PIGEON").tracking(2).font(.caption.weight(.semibold)) }.foregroundStyle(Color.pigeonGreen)
                    .padding(.top, 36)
                Image(systemName: "bird.fill")
                    .font(.system(size: 68, weight: .light))
                    .frame(width: 136, height: 136)
                    .foregroundStyle(Color.pigeonGreen)
                    .background(Color.pigeonGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 36))
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                Text("A little less\nleft behind.").font(.system(.largeTitle, design: .serif).weight(.medium))
                Text("A quiet place for a conversation between two people.")
                    .font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 22) {
                    feature("hand.tap", "Open when you're ready", "Each received message has its own 60-second viewing window.")
                    feature("hourglass", "No lasting message history", "Sent copies last 60 seconds after acceptance. Unopened messages last up to 24 hours.")
                    feature("person.2", "An invitation comes first", "Choose who can contact you, without sharing your address book.")
                }
                VStack(spacing: 12) {
                    Button {
                        model.reset(); preview = true
                    } label: { Text("Explore the interaction preview").frame(maxWidth: .infinity).padding(.vertical, 8) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    Text("Offline preview · fictional messages · no live encryption")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Live messaging build status") { showReadiness = true }.frame(minHeight: 44)
                }.padding(.top, 8)
            }.padding(28).frame(maxWidth: 600)
        }.background(Color(uiColor: .systemBackground))
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.pigeonGreen).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func unlock() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your conversations") { success, _ in
            Task { @MainActor in
                if success { locked = false; authenticationError = nil; model.tick() }
                else { authenticationError = "Unlock with your device passcode or biometrics, or leave the preview." }
            }
        }
    }
}

struct ChatListView: View {
    @Bindable var model: PreviewModel
    let exit: () -> Void
    @State private var privacy = false
    @State private var invitation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 9) {
                        Image(systemName: "flask")
                        Text("INTERACTION PREVIEW").font(.caption.weight(.semibold)).tracking(1)
                    }.foregroundStyle(Color.pigeonGreen)
                    Text("Fictional contact. Messages stay on this device and disappear when you leave the preview.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.listRowSeparator(.hidden)
                Section {
                    NavigationLink {
                        ConversationView(model: model)
                    } label: {
                        HStack(spacing: 14) {
                            Text("J").font(.title2.weight(.medium)).frame(width: 52, height: 52)
                                .background(Color.pigeonGreen.opacity(0.12), in: Circle()).foregroundStyle(Color.pigeonGreen)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Jamie").font(.headline)
                                Text(hasUnread ? "New message" : "No saved messages").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if hasUnread { Circle().fill(Color.pigeonGreen).frame(width: 9, height: 9).accessibilityLabel("Unread message") }
                        }.padding(.vertical, 8)
                    }
                }
                Section {
                    Label("No previews. No last seen. Just your people.", systemImage: "leaf")
                        .font(.footnote).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Privacy", systemImage: "lock.shield") { privacy = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("Add a person", systemImage: "square.and.pencil") { invitation = true } }
            }
            .sheet(isPresented: $privacy) { PrivacyView(exit: exit) }
            .sheet(isPresented: $invitation) { InvitationPreview() }
        }
    }
    private var hasUnread: Bool { model.ledger.records.values.contains { $0.state == .unopened } }
}

struct ConversationView: View {
    @Bindable var model: PreviewModel
    @State private var verify = false
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) { Image(systemName: "hourglass"); Text("60s after opening"); Spacer(); Text("Preview") }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        Text("Take a moment. Open each message when you're ready.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.vertical, 20)
                        ForEach(model.order, id: \.self) { id in
                            if let message = model.ledger.records[id] { messageRow(message).id(id) }
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 20)
                }
                .onChange(of: model.order.count) { _, _ in if let last = model.order.last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } } }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Write a preview message", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5).textContentType(.none).autocorrectionDisabled()
                    .padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                Button { model.sendPreview() } label: {
                    Image(systemName: "arrow.up").font(.headline).frame(width: 48, height: 48)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                    .disabled(!MessageLimits.validateText(model.draft)).accessibilityLabel("Send preview message")
            }.padding(14)
            if model.draft.utf8.count > MessageLimits.maximumTextBytes {
                Text("Message exceeds the 4 KiB limit.").font(.caption).foregroundStyle(.red).padding(.bottom, 8)
            }
        }
        .navigationTitle("Jamie").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Contact verification", systemImage: "person.crop.circle.badge.questionmark") { verify = true } } }
        .onReceive(tick) { _ in model.tick() }
        .sheet(isPresented: $verify) {
            InformationSheet(title: "Verify your contact", icon: "qrcode.viewfinder", text: "In live messaging, compare a safety number or scan each other's code through a trusted channel. This fictional preview contact has no cryptographic identity and is not verified.")
        }
        .alert("Message unavailable", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    @ViewBuilder private func messageRow(_ message: MessageMetadata) -> some View {
        let outgoing = message.direction == .outgoing
        HStack {
            if outgoing { Spacer(minLength: 40) }
            if message.state == .unopened {
                Button { model.open(message.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "envelope.badge").font(.title2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("New message").font(.headline)
                            Text("Open · 60 seconds").font(.subheadline)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(20).foregroundStyle(Color.pigeonGreen)
                        .background(Color.pigeonGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain).accessibilityLabel("New message. Open for up to 60 seconds.")
            } else if message.state == .expired {
                Label("Message disappeared", systemImage: "wind").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.visibleText[message.id] ?? "").font(.body).textSelection(.disabled)
                    HStack {
                        Image(systemName: "hourglass")
                        Text("\(Int(ceil(message.remaining(at: model.now))))s").monospacedDigit()
                        Spacer()
                        if outgoing { Text("Preview accepted") }
                    }.font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }.padding(18)
                    .background(outgoing ? Color.pigeonGreen.opacity(0.14) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityHint("This message disappears automatically. Its viewing window will not restart.")
            }
            if !outgoing { Spacer(minLength: 20) }
        }
    }
}

struct PrivacyView: View {
    let exit: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Your messages") {
                    Label("Received: 60 seconds after opening", systemImage: "hand.tap")
                    Label("Sent: 60 seconds after acceptance", systemImage: "paperplane")
                    Label("Unread: up to 24 hours", systemImage: "clock")
                }
                Section("Keep in mind") {
                    Text("A recipient can photograph or capture their screen. Disappearing messages cannot erase somebody else's copy.")
                    Text("This build is an offline interaction preview. Real messaging, account creation and contact verification are not available yet.")
                }.font(.subheadline)
                Section { Button("Leave and clear preview", role: .destructive) { dismiss(); exit() } }
            }.navigationTitle("Privacy").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct InvitationPreview: View {
    var body: some View {
        InformationSheet(title: "An invitation comes first", icon: "person.badge.plus", text: "Live messaging will let you share a private invitation link, scan a QR code or look up an exact username. Both people must agree before messaging begins. Invitations are not sent from this preview.")
    }
}
struct ReadinessView: View {
    var body: some View {
        InformationSheet(title: "Real messaging is still being built", icon: "hammer", text: "The interface preview is ready to explore. The live build still needs verified encryption and key transparency, a deployed relay, Apple signing and physical-device tests. It has not been independently security-reviewed.")
    }
}
struct InformationSheet: View {
    let title: String
    let icon: String
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: icon).font(.system(size: 48)).foregroundStyle(Color.pigeonGreen)
                    Text(title).font(.largeTitle.weight(.semibold))
                    Text(text).font(.body).foregroundStyle(.secondary)
                }.padding(28).frame(maxWidth: 600)
            }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
