import XCTest
@testable import AndroidTVRemoteControl

final class VarintFrameCodecTests: XCTestCase {
    func testDecodesFrameFragmentedAcrossEveryByte() throws {
        let payload = Data(repeating: 0x5a, count: 300)
        let framed = VarintFrameEncoder.frame(payload)
        let decoder = VarintFrameDecoder()
        var decoded: [Data] = []

        for byte in framed {
            decoded.append(contentsOf: try decoder.append(Data([byte])))
        }

        XCTAssertEqual(decoded, [payload])
    }

    func testDecodesCoalescedFramesInOrder() throws {
        let payloads = [Data(), Data([0x01]), Data(repeating: 0x7f, count: 200)]
        let coalesced = payloads.reduce(into: Data()) { result, payload in
            result.append(VarintFrameEncoder.frame(payload))
        }

        XCTAssertEqual(try VarintFrameDecoder().append(coalesced), payloads)
    }

    func testRejectsMalformedFiveByteVarint() {
        let decoder = VarintFrameDecoder()

        XCTAssertThrowsError(try decoder.append(Data([0x80, 0x80, 0x80, 0x80, 0x80]))) { error in
            XCTAssertEqual(error as? VarintFrameDecoderError, .malformedLength)
        }
    }

    func testRejectsFrameLargerThanConfiguredLimitBeforePayloadArrives() {
        let decoder = VarintFrameDecoder(maximumFrameLength: 8)
        let prefix = Data(Encoder.encodeVarint(9))

        XCTAssertThrowsError(try decoder.append(prefix)) { error in
            XCTAssertEqual(error as? VarintFrameDecoderError, .frameTooLarge(9))
        }
    }

    func testDefaultLimitIsOneMiB() throws {
        let decoder = VarintFrameDecoder()
        let prefix = Data(Encoder.encodeVarint(UInt(1_048_577)))

        XCTAssertThrowsError(try decoder.append(prefix)) { error in
            XCTAssertEqual(error as? VarintFrameDecoderError, .frameTooLarge(1_048_577))
        }
    }

    func testEncoderProducesOneAtomicPrefixAndPayloadValue() throws {
        let payload = Data([0xde, 0xad, 0xbe, 0xef])
        let framed = VarintFrameEncoder.frame(payload)

        XCTAssertEqual(framed, Data([0x04, 0xde, 0xad, 0xbe, 0xef]))
        XCTAssertEqual(try VarintFrameDecoder().append(framed), [payload])
    }
}

final class TLSManagerTests: XCTestCase {
    func testTrustDecisionUsesEvaluatorResult() {
        XCTAssertTrue(TLSManager.trustDecision { true })
        XCTAssertFalse(TLSManager.trustDecision { false })
    }

    func testMissingTrustEvaluatorFailsClosed() {
        XCTAssertFalse(TLSManager.trustDecision(nil))
    }
}
