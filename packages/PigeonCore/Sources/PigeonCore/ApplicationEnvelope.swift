import Foundation

public enum EnvelopeError: Error, Equatable {
    case invalidPayload, unsupportedVersion, wrongParticipants, wrongMessage, malformedPadding
}

/// Application metadata goes INSIDE the library-encrypted payload. Service
/// acceptance time is returned later in the authenticated relay receipt.
public struct ApplicationPayload: Codable, Equatable, Sendable {
    public let version: Int
    public let messageID: String
    public let conversationID: UUID
    public let sender: UUID
    public let recipient: UUID
    public let expiryPolicy: Int
    public let text: String

    public init(messageID: String, conversationID: UUID, sender: UUID, recipient: UUID, text: String) {
        version = 1
        expiryPolicy = 1
        self.messageID = messageID
        self.conversationID = conversationID
        self.sender = sender
        self.recipient = recipient
        self.text = text
    }

    public func validate(messageID expectedID: String, conversationID expectedConversation: UUID,
                         sender expectedSender: UUID, recipient expectedRecipient: UUID) throws {
        guard version == 1, expiryPolicy == 1 else { throw EnvelopeError.unsupportedVersion }
        guard messageID == expectedID, conversationID == expectedConversation else { throw EnvelopeError.wrongMessage }
        guard sender == expectedSender, recipient == expectedRecipient, sender != recipient else { throw EnvelopeError.wrongParticipants }
        guard messageID.utf8.count == 64,
              messageID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              MessageLimits.validateText(text) else { throw EnvelopeError.invalidPayload }
    }
}

/// Framing/padding only; this is not encryption. Pass its output unchanged to
/// the maintained messaging library, and decode only authenticated plaintext.
public enum EnvelopeCodec {
    // JSON escaping can expand a 4 KiB UTF-8 string. Leave room within the
    // relay's 32 KiB limit for the native protocol envelope and KEM material.
    public static let maximumPaddedBytes = 28_672

    public static func encode(_ payload: ApplicationPayload) throws -> Data {
        try payload.validate(messageID: payload.messageID, conversationID: payload.conversationID,
                             sender: payload.sender, recipient: payload.recipient)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = try encoder.encode(payload)
        let count = body.count + 4
        let size = ((count + MessageLimits.paddingBucketBytes - 1) / MessageLimits.paddingBucketBytes) * MessageLimits.paddingBucketBytes
        guard size <= maximumPaddedBytes else { throw EnvelopeError.invalidPayload }
        let length = UInt32(body.count)
        var result = Data([UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)])
        result.append(body)
        result.append(Data(repeating: 0, count: size - count))
        return result
    }

    public static func decodeAuthenticated(_ padded: Data) throws -> ApplicationPayload {
        guard padded.count >= MessageLimits.paddingBucketBytes,
              padded.count <= maximumPaddedBytes,
              padded.count % MessageLimits.paddingBucketBytes == 0 else { throw EnvelopeError.malformedPadding }
        let bytes = Array(padded)
        let count = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, Int(count) <= bytes.count - 4 else { throw EnvelopeError.malformedPadding }
        let end = 4 + Int(count)
        guard bytes[end...].allSatisfy({ $0 == 0 }), bytes.count - end < MessageLimits.paddingBucketBytes else {
            throw EnvelopeError.malformedPadding
        }
        let payload = try JSONDecoder().decode(ApplicationPayload.self, from: Data(bytes[4..<end]))
        try payload.validate(messageID: payload.messageID, conversationID: payload.conversationID,
                             sender: payload.sender, recipient: payload.recipient)
        return payload
    }
}
