import Foundation
import Observation
import PigeonCore

/// Fictional, memory-only UI fixtures. Never used by a live transport.
@MainActor @Observable
final class PreviewModel {
    private(set) var ledger = MessageLedger()
    private(set) var order: [String] = []
    private(set) var visibleText: [String: String] = [:]
    private var unopenedFixtures: [String: String] = [:]
    private var clock: TrustedClock?
    var draft = ""
    var errorMessage: String?

    init() { reset() }

    var now: Date {
        // Preview time is a local fixture. Production must obtain an
        // authenticated service-time sample before constructing this clock.
        (try? clock?.now(uptime: ProcessInfo.processInfo.systemUptime)) ?? .distantFuture
    }

    func reset() {
        ledger = MessageLedger(); order = []; visibleText = [:]; unopenedFixtures = [:]; draft = ""
        let time = Date()
        clock = try? TrustedClock(serverTime: time, uptime: ProcessInfo.processInfo.systemUptime)
        addFixture("Meet by the little bookshop at six?", direction: .incoming)
        addFixture("I'll bring the book you mentioned. 📚", direction: .incoming)
    }

    private func addFixture(_ text: String, direction: MessageMetadata.Direction) {
        do {
            let time = now
            let message = try MessageMetadata(id: UUID().uuidString, direction: direction, acceptedAt: time, unreadDeadline: time.addingTimeInterval(86_400))
            try ledger.receive(message, at: time)
            order.append(message.id)
            if direction == .incoming { unopenedFixtures[message.id] = text }
            else { visibleText[message.id] = text }
        } catch { errorMessage = "The preview could not create a message." }
    }

    func open(_ id: String) {
        do {
            _ = try ledger.open(id, at: now)
            // Remove the fixture before making text visible, matching the
            // direction of the production consume-before-render operation.
            visibleText[id] = unopenedFixtures.removeValue(forKey: id)
        } catch { errorMessage = "This message is no longer available." }
    }

    func sendPreview() {
        guard MessageLimits.validateText(draft) else { return }
        let text = draft
        draft = ""
        addFixture(text, direction: .outgoing)
    }

    func tick() {
        ledger.expire(at: now)
        for (id, value) in ledger.records where value.state == .expired {
            visibleText.removeValue(forKey: id)
            unopenedFixtures.removeValue(forKey: id)
        }
    }

    func cover() { draft = ""; tick() }
    func discardAll() {
        draft = ""; visibleText = [:]; unopenedFixtures = [:]
        ledger = MessageLedger(); order = []
    }
}

