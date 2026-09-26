import Foundation
import LibSignalClient
import XCTest

/// Real-library integration tests. Test-only in-memory stores and certificate
/// authority. None of these credentials or stores are used by the app.
final class ProtocolProbeTests: XCTestCase {
    private struct Pair {
        let alice = InMemorySignalProtocolStore()
        let bob = InMemorySignalProtocolStore()
        let aliceAddress: ProtocolAddress
        let bobAddress: ProtocolAddress

        init() throws {
            aliceAddress = try ProtocolAddress(name: UUID().uuidString.lowercased(), deviceId: 1)
            bobAddress = try ProtocolAddress(name: UUID().uuidString.lowercased(), deviceId: 1)
            let context = NullContext()
            let identity = try bob.identityKeyPair(context: context)
            let signed = PrivateKey.generate()
            let kem = KEMKeyPair.generate()
            let signature = identity.privateKey.generateSignature(message: signed.publicKey.serialize())
            let kemSignature = identity.privateKey.generateSignature(message: kem.publicKey.serialize())
            try bob.storeSignedPreKey(SignedPreKeyRecord(id: 1, timestamp: 0, privateKey: signed, signature: signature), id: 1, context: context)
            try bob.storeKyberPreKey(KyberPreKeyRecord(id: 2, timestamp: 0, keyPair: kem, signature: kemSignature), id: 2, context: context)
            let bundle = try PreKeyBundle(
                registrationId: bob.localRegistrationId(context: context), deviceId: 1,
                signedPrekeyId: 1, signedPrekey: signed.publicKey, signedPrekeySignature: signature,
                identity: identity.identityKey, kyberPrekeyId: 2, kyberPrekey: kem.publicKey, kyberPrekeySignature: kemSignature
            )
            try processPreKeyBundle(bundle, for: bobAddress, ourAddress: aliceAddress, sessionStore: alice, identityStore: alice, context: context)
        }

        func encrypt(_ value: Data) throws -> CiphertextMessage {
            try signalEncrypt(message: value, for: bobAddress, localAddress: aliceAddress, sessionStore: alice, identityStore: alice, context: NullContext())
        }
        func receiveInitial(_ value: Data) throws -> Data {
            try signalDecryptPreKey(message: PreKeySignalMessage(bytes: value), from: aliceAddress, localAddress: bobAddress,
                sessionStore: bob, identityStore: bob, preKeyStore: bob, signedPreKeyStore: bob, kyberPreKeyStore: bob, context: NullContext())
        }
    }

    func testHybridSessionAndBidirectionalReply() throws {
        let pair = try Pair()
        let plaintext = Data("Message fixture".utf8)
        let ciphertext = try pair.encrypt(plaintext)
        XCTAssertEqual(ciphertext.messageType, .preKey)
        XCTAssertNil(ciphertext.serialize().range(of: plaintext))
        XCTAssertEqual(try pair.receiveInitial(ciphertext.serialize()), plaintext)

        let replyText = Data("Reply fixture".utf8)
        let reply = try signalEncrypt(message: replyText, for: pair.aliceAddress, localAddress: pair.bobAddress,
            sessionStore: pair.bob, identityStore: pair.bob, context: NullContext())
        XCTAssertEqual(reply.messageType, .whisper)
        let recovered = try signalDecrypt(message: SignalMessage(bytes: reply.serialize()), from: pair.bobAddress, to: pair.aliceAddress,
            sessionStore: pair.alice, identityStore: pair.alice, context: NullContext())
        XCTAssertEqual(recovered, replyText)
    }

    func testReplayIsRejected() throws {
        let pair = try Pair()
        let ciphertext = try pair.encrypt(Data("Replay fixture".utf8)).serialize()
        _ = try pair.receiveInitial(ciphertext)
        XCTAssertThrowsError(try pair.receiveInitial(ciphertext))
    }

    func testTamperedCiphertextIsRejected() throws {
        let pair = try Pair()
        var ciphertext = try pair.encrypt(Data("Tamper fixture".utf8)).serialize()
        ciphertext[ciphertext.index(before: ciphertext.endIndex)] ^= 0x01
        XCTAssertThrowsError(try pair.receiveInitial(ciphertext))
    }

    func testSealedSenderEnvelopeAndCertificateValidation() throws {
        let pair = try Pair()
        let root = PrivateKey.generate()
        let signer = PrivateKey.generate()
        let serverCertificate = try ServerCertificate(keyId: 1, publicKey: signer.publicKey, trustRoot: root)
        let sender = try SealedSenderAddress(e164: nil, uuidString: pair.aliceAddress.name, deviceId: 1)
        let identity = try pair.alice.identityKeyPair(context: NullContext())
        let certificate = try SenderCertificate(sender: sender, publicKey: identity.publicKey, expiration: 1_000_000,
            signerCertificate: serverCertificate, signerKey: signer)
        let plaintext = Data("Sealed sender fixture".utf8)
        let content = try UnidentifiedSenderMessageContent(pair.encrypt(plaintext), from: certificate, contentHint: .default, groupId: Data())
        let envelope = try sealedSenderEncrypt(content, for: pair.bobAddress, identityStore: pair.alice, context: NullContext())
        XCTAssertNil(envelope.range(of: Data(pair.aliceAddress.name.utf8)))
        let recovered = try UnidentifiedSenderMessageContent(message: envelope, identityStore: pair.bob, context: NullContext())
        XCTAssertTrue(recovered.senderCertificate.validate(trustRoot: root.publicKey, time: 1))
        XCTAssertFalse(recovered.senderCertificate.validate(trustRoot: PrivateKey.generate().publicKey, time: 1))
        XCTAssertFalse(recovered.senderCertificate.validate(trustRoot: root.publicKey, time: 1_000_001))
        XCTAssertEqual(recovered.senderCertificate.senderUuid, pair.aliceAddress.name)
        XCTAssertEqual(try pair.receiveInitial(recovered.contents), plaintext)
    }
}
