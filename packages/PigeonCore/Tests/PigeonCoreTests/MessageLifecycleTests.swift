import Foundation
import Testing
@testable import PigeonCore

private let accepted = Date(timeIntervalSince1970: 1_800_000_000)
private func incoming(_ id: String = "one") throws -> MessageMetadata {
    try MessageMetadata(id: id, direction: .incoming, acceptedAt: accepted, unreadDeadline: accepted.addingTimeInterval(86_400))
}

@Test func receivingDoesNotStartVisibleTimer() throws {
    var ledger = MessageLedger()
    try ledger.receive(incoming(), at: accepted)
    #expect(ledger.records["one"]?.state == .unopened)
    #expect(ledger.records["one"]?.visibleDeadline == nil)
    let opened = try ledger.open("one", at: accepted.addingTimeInterval(200))
    #expect(opened.visibleDeadline == accepted.addingTimeInterval(260))
}
@Test func openingNearUnreadDeadlineUsesShorterDuration() throws {
    var value = try incoming()
    try value.open(at: accepted.addingTimeInterval(86_390))
    #expect(value.remaining(at: accepted.addingTimeInterval(86_390)) == 10)
    value.expire(at: accepted.addingTimeInterval(86_400))
    #expect(value.state == .expired)
}
@Test func openingAtDeadlineIsRejected() throws {
    var value = try incoming()
    #expect(throws: LifecycleError.unavailable) { try value.open(at: accepted.addingTimeInterval(86_400)) }
}
@Test func duplicateAndReopenCannotResetDeadline() throws {
    var ledger = MessageLedger()
    try ledger.receive(incoming(), at: accepted)
    _ = try ledger.open("one", at: accepted)
    #expect(throws: LifecycleError.duplicate) { try ledger.receive(incoming(), at: accepted.addingTimeInterval(20)) }
    #expect(throws: LifecycleError.unavailable) { try ledger.open("one", at: accepted.addingTimeInterval(30)) }
    #expect(ledger.records["one"]?.visibleDeadline == accepted.addingTimeInterval(60))
}
@Test func senderExpiryDoesNotWaitForRecipient() throws {
    var value = try MessageMetadata(id: "sent", direction: .outgoing, acceptedAt: accepted, unreadDeadline: accepted.addingTimeInterval(86_400))
    value.expire(at: accepted.addingTimeInterval(60))
    #expect(value.state == .expired)
}
@Test func processRestartDiscardsOpenedButPreservesUnreadMetadata() throws {
    var first = try incoming("opened")
    try first.open(at: accepted)
    var ledger = MessageLedger()
    try ledger.restore([first, incoming("unopened")], at: accepted.addingTimeInterval(10))
    #expect(ledger.records["opened"]?.state == .expired)
    #expect(ledger.records["unopened"]?.state == .unopened)
}
@Test func monotonicTimeIgnoresWallClockRollback() throws {
    let clock = try TrustedClock(serverTime: accepted, uptime: 100)
    #expect(try clock.now(uptime: 160) == accepted.addingTimeInterval(60))
    #expect(throws: LifecycleError.untrustedTime) { try clock.now(uptime: 99) }
    #expect(throws: LifecycleError.untrustedTime) { try clock.now(uptime: .nan) }
}
@Test func futureExpiredAndContradictoryMetadataFailClosed() throws {
    var ledger = MessageLedger()
    #expect(throws: LifecycleError.unavailable) { try ledger.receive(incoming(), at: accepted.addingTimeInterval(-1)) }
    #expect(throws: LifecycleError.unavailable) { try ledger.receive(incoming(), at: accepted.addingTimeInterval(86_400)) }
    #expect(throws: LifecycleError.invalidEnvelope) { try MessageMetadata(id: "bad", direction: .incoming, acceptedAt: accepted, unreadDeadline: accepted.addingTimeInterval(100)) }
}
@Test func textLimitCountsUTF8Bytes() {
    #expect(MessageLimits.validateText(String(repeating: "a", count: 4_096)))
    #expect(!MessageLimits.validateText(String(repeating: "a", count: 4_097)))
    #expect(!MessageLimits.validateText(String(repeating: "🕊", count: 2_000)))
    #expect(!MessageLimits.validateText(" \n "))
}
