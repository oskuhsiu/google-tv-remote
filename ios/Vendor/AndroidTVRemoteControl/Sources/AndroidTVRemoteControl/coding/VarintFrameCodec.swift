import Foundation

enum VarintFrameDecoderError: Error, Equatable {
    case malformedLength
    case frameTooLarge(Int)
}

final class VarintFrameDecoder {
    static let defaultMaximumFrameLength = 1_048_576

    private let maximumFrameLength: Int
    private var buffer = Data()

    init(maximumFrameLength: Int = defaultMaximumFrameLength) {
        precondition(maximumFrameLength >= 0)
        self.maximumFrameLength = maximumFrameLength
    }

    func append(_ data: Data) throws -> [Data] {
        buffer.append(data)

        var frames: [Data] = []
        while let prefix = try decodeLengthPrefix() {
            guard prefix.length <= maximumFrameLength else {
                buffer.removeAll(keepingCapacity: false)
                throw VarintFrameDecoderError.frameTooLarge(prefix.length)
            }

            let frameEnd = prefix.byteCount + prefix.length
            guard buffer.count >= frameEnd else {
                break
            }

            let payloadStart = buffer.index(buffer.startIndex, offsetBy: prefix.byteCount)
            let payloadEnd = buffer.index(buffer.startIndex, offsetBy: frameEnd)
            frames.append(Data(buffer[payloadStart..<payloadEnd]))
            buffer.removeFirst(frameEnd)
        }
        return frames
    }

    func reset() {
        buffer.removeAll(keepingCapacity: false)
    }

    private func decodeLengthPrefix() throws -> (length: Int, byteCount: Int)? {
        var value: UInt64 = 0

        for index in 0..<min(buffer.count, 5) {
            let dataIndex = buffer.index(buffer.startIndex, offsetBy: index)
            let byte = buffer[dataIndex]
            if index == 4 && byte > 0x0f {
                buffer.removeAll(keepingCapacity: false)
                throw VarintFrameDecoderError.malformedLength
            }

            value |= UInt64(byte & 0x7f) << UInt64(index * 7)
            if byte & 0x80 == 0 {
                return (Int(value), index + 1)
            }
        }

        if buffer.count >= 5 {
            buffer.removeAll(keepingCapacity: false)
            throw VarintFrameDecoderError.malformedLength
        }
        return nil
    }
}

enum VarintFrameEncoder {
    static func frame(_ payload: Data) -> Data {
        var framed = Data(Encoder.encodeVarint(UInt(payload.count)))
        framed.append(payload)
        return framed
    }
}
