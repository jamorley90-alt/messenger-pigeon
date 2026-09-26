import Foundation
import Testing
@testable import PigeonCore

private func payload(_ text: String = "Hello") -> ApplicationPayload {
    .init(messageID: String(repeating: "a", count: 64), conversationID: UUID(), sender: UUID(), recipient: UUID(), text: text)
}

@Test func framingRoundTripAndEqualBucketLengths() throws {
    let original = payload()
    let encoded = try EnvelopeCodec.encode(original)
    #expect(try EnvelopeCodec.decodeAuthenticated(encoded) == original)
    #expect(encoded.count % 256 == 0)
    #expect(try EnvelopeCodec.encode(payload("Hello!")).count == encoded.count)
}
@Test func wrongIdentityConversationAndMessageAreRejected() throws {
    let original = payload()
    #expect(throws: EnvelopeError.wrongParticipants) {
        try original.validate(messageID: original.messageID, conversationID: original.conversationID, sender: UUID(), recipient: original.recipient)
    }
    #expect(throws: EnvelopeError.wrongMessage) {
        try original.validate(messageID: String(repeating: "b", count: 64), conversationID: original.conversationID, sender: original.sender, recipient: original.recipient)
    }
}
@Test func malformedFramingIsRejected() throws {
    var encoded = try EnvelopeCodec.encode(payload())
    encoded[0] = 255
    #expect(throws: EnvelopeError.malformedPadding) { try EnvelopeCodec.decodeAuthenticated(encoded) }
    #expect(throws: EnvelopeError.malformedPadding) { try EnvelopeCodec.decodeAuthenticated(Data(repeating: 0, count: 255)) }
}
@Test func protocolVersionCannotSilentlyDowngrade() throws {
    let original = payload()
    let data = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["version"] = 0
    let downgraded = try JSONDecoder().decode(ApplicationPayload.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(throws: EnvelopeError.unsupportedVersion) { try EnvelopeCodec.encode(downgraded) }
}
