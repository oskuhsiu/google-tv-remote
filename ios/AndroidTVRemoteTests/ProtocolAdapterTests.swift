import Foundation
import Security
import SwiftProtobuf
import XCTest
@testable import AndroidTVRemote

final class ProtocolAdapterTests: XCTestCase {
    func testFrameDecoderAcceptsEveryFragmentBoundary() throws {
        let payloads = [Data([0x08, 0x01]), Data(repeating: 0x7f, count: 300), Data()]
        let stream = payloads.reduce(into: Data()) { bytes, payload in
            bytes.append(FrameEncoder.frame(payload))
        }

        var decoder = FrameDecoder()
        var decoded: [Data] = []
        for byte in stream {
            decoded.append(contentsOf: try decoder.append(Data([byte])))
        }

        XCTAssertEqual(decoded, payloads)
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testFrameDecoderAcceptsCoalescedFrames() throws {
        let first = Data([0x01, 0x02])
        let second = Data([0x03, 0x04, 0x05])
        var stream = FrameEncoder.frame(first)
        stream.append(FrameEncoder.frame(second))

        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.append(stream), [first, second])
    }

    func testFrameDecoderAcceptsTwentyKiBBoundaryPayload() throws {
        let payload = Data(repeating: 0x5a, count: 20 * 1_024)
        let framed = FrameEncoder.frame(payload)
        var decoder = FrameDecoder()

        XCTAssertEqual(try decoder.append(Data(framed.prefix(2))), [])
        XCTAssertEqual(try decoder.append(Data(framed.dropFirst(2))), [payload])
    }

    func testFrameDecoderRejectsMalformedVarintAndRecoversAfterReset() throws {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data(repeating: 0x80, count: 5))) { error in
            XCTAssertEqual(error as? FrameDecoderError, .malformedLength)
        }
        XCTAssertEqual(decoder.bufferedByteCount, 0)

        let payload = Data([0x42])
        XCTAssertEqual(try decoder.append(FrameEncoder.frame(payload)), [payload])
    }

    func testFrameDecoderRejectsOversizeBeforeBufferingPayload() {
        var decoder = FrameDecoder(maximumFrameLength: 4)
        XCTAssertThrowsError(try decoder.append(Data([0x05]))) { error in
            XCTAssertEqual(error as? FrameDecoderError, .frameTooLarge(5))
        }
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testFrameDecoderRejectsTruncatedFrameAtEOF() throws {
        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.append(Data([0x03, 0xaa])), [])
        XCTAssertThrowsError(try decoder.finish()) { error in
            XCTAssertEqual(error as? FrameDecoderError, .truncatedFrame(2))
        }
        XCTAssertNoThrow(try decoder.finish())
    }

    func testOutboundWriterSendsEachCompleteFrameAtomically() async throws {
        let recorder = RecordingSink()
        let writer = OutboundWriter { recorder.record($0) }
        let first = Data([0x08, 0x01])
        let second = Data(repeating: 0xaa, count: 130)

        try writer.send(payload: first)
        try writer.send(payload: second)

        XCTAssertEqual(recorder.frames, [FrameEncoder.frame(first), FrameEncoder.frame(second)])
    }

    func testAllAppCommandsUseGeneratedProtobufMappings() throws {
        for command in RemoteCommand.allCases {
            let payload = try RemotePayloadFactory.key(command: command, action: .short)
            let message = try Remote_RemoteMessage(serializedBytes: payload)

            XCTAssertTrue(message.hasRemoteKeyInject)
            XCTAssertEqual(message.remoteKeyInject.keyCode.rawValue, command.androidKeyCode)
            XCTAssertEqual(message.remoteKeyInject.direction, .short)
        }
    }

    func testOnlySelectSupportsProtocolLongDirections() throws {
        let start = try RemotePayloadFactory.key(command: .select, action: .startLong)
        let end = try RemotePayloadFactory.key(command: .select, action: .endLong)

        XCTAssertEqual(
            try Remote_RemoteMessage(serializedBytes: start).remoteKeyInject.direction,
            .startLong
        )
        XCTAssertEqual(
            try Remote_RemoteMessage(serializedBytes: end).remoteKeyInject.direction,
            .endLong
        )
        XCTAssertThrowsError(try RemotePayloadFactory.key(command: .up, action: .startLong))
    }

    func testPeerTrustPolicyIsFailClosedAndCaseInsensitive() {
        XCTAssertFalse(PeerTrustGate.accepts(expected: "", actual: "abc"))
        XCTAssertFalse(PeerTrustGate.accepts(expected: "abc", actual: "def"))
        XCTAssertTrue(PeerTrustGate.accepts(expected: "A1B2", actual: "a1b2"))

        let device = RemoteDevice(id: "abc", name: "TV", host: "192.0.2.1", locator: nil)
        XCTAssertEqual(
            AdapterErrorPolicy.failure(
                error: .connectionCanceled,
                for: .changed(expected: "abc", actual: "def"),
                device: device
            ),
            .failed(device, reason: .trustChanged, recoverable: false)
        )
        XCTAssertEqual(
            AdapterErrorPolicy.failure(
                error: .connectionCanceled,
                for: .notEvaluated,
                device: device
            ),
            .failed(device, reason: .networkUnreachable, recoverable: true)
        )
        XCTAssertEqual(
            AdapterErrorPolicy.failure(
                error: .connectionClosed,
                for: .accepted("abc"),
                device: device,
                wasConnected: true
            ),
            .failed(device, reason: .connectionLost, recoverable: true)
        )
    }

    func testSecurityBackedIdentityRoundTripsWithoutChangingFingerprint() throws {
        let store = IdentityStore(namespace: "test.\(UUID().uuidString)")
        try? store.deleteAll()
        defer { try? store.deleteAll() }

        let created = try store.loadOrCreate()
        let loaded = try XCTUnwrap(store.load())

        XCTAssertEqual(created.fingerprint, loaded.fingerprint)
        XCTAssertEqual(try store.status(matching: created.fingerprint), .matches)
        XCTAssertEqual(created.fingerprint.count, 64)
        XCTAssertEqual(CFGetTypeID(created.identity), SecIdentityGetTypeID())
        XCTAssertEqual(CFGetTypeID(created.publicKey), SecKeyGetTypeID())

        let importItems = try XCTUnwrap(created.tlsImportItems as? [[String: Any]])
        let importedIdentity = try XCTUnwrap(importItems.first?[kSecImportItemIdentity as String])
        XCTAssertEqual(CFGetTypeID(importedIdentity as CFTypeRef), SecIdentityGetTypeID())

    }
}

private final class RecordingSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Data] = []

    var frames: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ frame: Data) {
        lock.lock()
        storage.append(frame)
        lock.unlock()
    }
}
