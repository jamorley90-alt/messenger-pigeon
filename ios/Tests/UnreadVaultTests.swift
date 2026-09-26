import Foundation
import XCTest
@testable import MessengerPigeon

final class UnreadVaultTests: XCTestCase {
    func testConsumeDestroysDurableKeyBeforeReturningText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try UnreadVault(directory: directory, keychainService: "pigeon-tests.\(UUID().uuidString)")
        let now = Date()
        let id = UUID()
        let value = UnreadVault.Unread(id: id, acceptedAt: now, unreadDeadline: now.addingTimeInterval(86_400), text: "A private test fixture")
        try await vault.save(value)
        let ciphertext = try Data(contentsOf: directory.appendingPathComponent(id.uuidString).appendingPathExtension("sealed"))
        XCTAssertNil(ciphertext.range(of: Data(value.text.utf8)))
        let read = try await vault.consume(id, trustedNow: now)
        XCTAssertEqual(read.text, value.text)
        do { _ = try await vault.consume(id, trustedNow: now); XCTFail("Consumed message reopened") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(id.uuidString).appendingPathExtension("sealed").path))
        try FileManager.default.removeItem(at: directory)
    }

    func testExpiredUnreadCannotBeOpened() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try UnreadVault(directory: directory, keychainService: "pigeon-tests.\(UUID().uuidString)")
        let now = Date(); let id = UUID()
        try await vault.save(.init(id: id, acceptedAt: now, unreadDeadline: now.addingTimeInterval(86_400), text: "Expired fixture"))
        do { _ = try await vault.consume(id, trustedNow: now.addingTimeInterval(86_400)); XCTFail("Expired message opened") } catch { }
        try FileManager.default.removeItem(at: directory)
    }

    func testFileIsExcludedFromBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try UnreadVault(directory: directory, keychainService: "pigeon-tests.\(UUID().uuidString)")
        let now = Date(); let id = UUID()
        try await vault.save(.init(id: id, acceptedAt: now, unreadDeadline: now.addingTimeInterval(86_400), text: "Protection fixture"))
        let file = directory.appendingPathComponent(id.uuidString).appendingPathExtension("sealed")
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try await vault.discard(id)
        try FileManager.default.removeItem(at: directory)
    }

    func testFileHasCompleteProtectionOnDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("File Data Protection requires a physical iPhone; simulator success cannot attest to protection.")
        #else
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try UnreadVault(directory: directory, keychainService: "pigeon-tests.\(UUID().uuidString)")
        let now = Date(); let id = UUID()
        try await vault.save(.init(id: id, acceptedAt: now, unreadDeadline: now.addingTimeInterval(86_400), text: "Protection fixture"))
        let file = directory.appendingPathComponent(id.uuidString).appendingPathExtension("sealed")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
        try await vault.discard(id)
        try FileManager.default.removeItem(at: directory)
        #endif
    }
}
