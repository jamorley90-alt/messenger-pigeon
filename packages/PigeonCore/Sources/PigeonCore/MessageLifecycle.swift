import Foundation

public enum LifecycleError: Error, Equatable {
    case untrustedTime, invalidEnvelope, duplicate, unavailable
}

/// An authenticated service-time sample anchored to the process's monotonic
/// clock. It must not be restored after reboot or reused across process launches.
public struct TrustedClock: Sendable {
    private let serverTime: Date
    private let uptime: TimeInterval
    public init(serverTime: Date, uptime: TimeInterval) throws {
        guard uptime.isFinite, uptime >= 0, serverTime.timeIntervalSince1970.isFinite else { throw LifecycleError.untrustedTime }
        self.serverTime = serverTime
        self.uptime = uptime
    }
    public func now(uptime current: TimeInterval) throws -> Date {
        guard current.isFinite, current >= uptime else { throw LifecycleError.untrustedTime }
        return serverTime.addingTimeInterval(current - uptime)
    }
}

public struct MessageMetadata: Codable, Equatable, Sendable, Identifiable {
    public enum Direction: String, Codable, Sendable { case incoming, outgoing }
    public enum State: String, Codable, Sendable { case unopened, opened, sent, expired }
    public let id: String
    public let direction: Direction
    public let acceptedAt: Date
    public let unreadDeadline: Date
    public private(set) var state: State
    public private(set) var visibleDeadline: Date?

    public init(id: String, direction: Direction, acceptedAt: Date, unreadDeadline: Date) throws {
        guard !id.isEmpty,
              acceptedAt.timeIntervalSince1970.isFinite,
              unreadDeadline.timeIntervalSince1970.isFinite,
              unreadDeadline == acceptedAt.addingTimeInterval(86_400) else { throw LifecycleError.invalidEnvelope }
        self.id = id
        self.direction = direction
        self.acceptedAt = acceptedAt
        self.unreadDeadline = unreadDeadline
        self.state = direction == .incoming ? .unopened : .sent
        self.visibleDeadline = direction == .outgoing ? acceptedAt.addingTimeInterval(60) : nil
    }

    public func remaining(at now: Date) -> TimeInterval {
        guard state != .expired else { return 0 }
        return max(0, (visibleDeadline ?? unreadDeadline).timeIntervalSince(now))
    }
    public mutating func open(at now: Date) throws {
        guard state == .unopened, now >= acceptedAt, now < unreadDeadline else { throw LifecycleError.unavailable }
        state = .opened
        visibleDeadline = min(now.addingTimeInterval(60), unreadDeadline)
    }
    public mutating func expire(at now: Date) {
        if remaining(at: now) <= 0 { state = .expired; visibleDeadline = nil }
    }
    public mutating func discardVisibleContentAfterRestart() {
        if state == .opened || state == .sent { state = .expired; visibleDeadline = nil }
    }
}

/// Holds content-free lifecycle metadata. Production persistence must commit
/// replay state with protocol updates before acknowledging network delivery.
public struct MessageLedger: Sendable {
    public private(set) var records: [String: MessageMetadata] = [:]
    public init() {}
    public mutating func receive(_ message: MessageMetadata, at now: Date) throws {
        guard records[message.id] == nil else { throw LifecycleError.duplicate }
        guard now >= message.acceptedAt, now < message.unreadDeadline else { throw LifecycleError.unavailable }
        var value = message
        value.expire(at: now)
        records[message.id] = value
    }
    public mutating func open(_ id: String, at now: Date) throws -> MessageMetadata {
        guard var value = records[id] else { throw LifecycleError.unavailable }
        try value.open(at: now)
        records[id] = value
        return value
    }
    public mutating func expire(at now: Date) {
        for id in Array(records.keys) { records[id]?.expire(at: now) }
    }
    public mutating func restore(_ metadata: [MessageMetadata], at now: Date) throws {
        var replacement: [String: MessageMetadata] = [:]
        for var value in metadata {
            guard replacement[value.id] == nil,
                  value.unreadDeadline == value.acceptedAt.addingTimeInterval(86_400),
                  value.acceptedAt <= now else { throw LifecycleError.invalidEnvelope }
            value.discardVisibleContentAfterRestart()
            value.expire(at: now)
            replacement[value.id] = value
        }
        records = replacement
    }
}

public enum MessageLimits {
    public static let maximumTextBytes = 4_096
    public static let paddingBucketBytes = 256
    public static func validateText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= maximumTextBytes
    }
}
