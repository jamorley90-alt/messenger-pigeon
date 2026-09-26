import CryptoKit
import Foundation
import Security

enum VaultError: Error { case keychain(OSStatus), invalidRecord, unavailable, duplicate }

/// Single-device unread storage primitive, not yet connected to the network
/// protocol store. Ratchet/replay state needs a separate transactional store.
/// Callers must obtain trusted time before invoking consume or purge.
actor UnreadVault {
    private let directory: URL
    private let keychainService: String

    struct Unread: Codable, Sendable {
        let id: UUID
        let acceptedAt: Date
        let unreadDeadline: Date
        let text: String
    }

    init(directory: URL, keychainService: String) throws {
        self.directory = directory
        self.keychainService = keychainService
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var location = directory
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try location.setResourceValues(attributes)
    }

    func save(_ record: Unread) throws {
        guard record.unreadDeadline == record.acceptedAt.addingTimeInterval(86_400),
              !record.text.isEmpty, record.text.utf8.count <= 4_096 else { throw VaultError.invalidRecord }
        let file = path(record.id)
        guard !FileManager.default.fileExists(atPath: file.path) else { throw VaultError.duplicate }
        let key = SymmetricKey(size: .bits256)
        let plaintext = try JSONEncoder().encode(record)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: Data(record.id.uuidString.utf8))
        guard let ciphertext = box.combined else { throw VaultError.invalidRecord }
        var attributes = query(record.id)
        attributes[kSecValueData] = key.withUnsafeBytes { Data($0) }
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(attributes as CFDictionary, nil)
        guard result == errSecSuccess else { throw VaultError.keychain(result) }
        do {
            try ciphertext.write(to: file, options: [.atomic, .completeFileProtection])
            var excludedFile = file
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excludedFile.setResourceValues(values)
        } catch {
            _ = SecItemDelete(query(record.id) as CFDictionary)
            throw error
        }
    }

    /// Deletes the Keychain content key before returning plaintext. A crash
    /// between deleting the key and removing the file leaves unusable ciphertext.
    func consume(_ id: UUID, trustedNow: Date) throws -> Unread {
        let record = try read(id)
        guard trustedNow >= record.acceptedAt, trustedNow < record.unreadDeadline else {
            if trustedNow >= record.unreadDeadline { try discard(id) }
            throw VaultError.unavailable
        }
        try discard(id)
        return record
    }

    func discard(_ id: UUID) throws {
        let result = SecItemDelete(query(id) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw VaultError.keychain(result) }
        let file = path(id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    func purge(trustedNow: Date) throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard file.pathExtension == "sealed", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            do {
                let record = try read(id)
                if trustedNow >= record.unreadDeadline { try discard(id) }
            } catch VaultError.keychain(let code) where code == errSecItemNotFound {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    private func read(_ id: UUID) throws -> Unread {
        var attributes = query(id)
        attributes[kSecReturnData] = true
        attributes[kSecMatchLimit] = kSecMatchLimitOne
        var value: CFTypeRef?
        let result = SecItemCopyMatching(attributes as CFDictionary, &value)
        guard result == errSecSuccess, let keyData = value as? Data else { throw VaultError.keychain(result) }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: path(id)))
        let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: keyData), authenticating: Data(id.uuidString.utf8))
        let record = try JSONDecoder().decode(Unread.self, from: plaintext)
        guard record.id == id, record.unreadDeadline == record.acceptedAt.addingTimeInterval(86_400) else { throw VaultError.invalidRecord }
        return record
    }
    private func path(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("sealed") }
    private func query(_ id: UUID) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: id.uuidString, kSecAttrSynchronizable: false]
    }
}
