import Foundation

enum FrameDecoderError: Error, Equatable {
    case malformedLength
    case frameTooLarge(Int)
    case truncatedFrame(Int)
}

struct FrameDecoder {
    static let defaultMaximumFrameLength = 1_048_576

    private(set) var bufferedByteCount = 0
    private var buffer = Data()
    private let maximumFrameLength: Int

    init(maximumFrameLength: Int = Self.defaultMaximumFrameLength) {
        precondition(maximumFrameLength >= 0)
        self.maximumFrameLength = maximumFrameLength
    }

    mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []

        do {
            while let prefix = try decodedLengthPrefix() {
                guard prefix.length <= maximumFrameLength else {
                    throw FrameDecoderError.frameTooLarge(prefix.length)
                }
                let totalLength = prefix.byteCount + prefix.length
                guard buffer.count >= totalLength else { break }

                let payloadStart = buffer.index(buffer.startIndex, offsetBy: prefix.byteCount)
                let payloadEnd = buffer.index(payloadStart, offsetBy: prefix.length)
                frames.append(Data(buffer[payloadStart..<payloadEnd]))
                buffer.removeSubrange(buffer.startIndex..<payloadEnd)
            }

            if buffer.count > maximumFrameLength + 5 {
                throw FrameDecoderError.frameTooLarge(buffer.count)
            }
            bufferedByteCount = buffer.count
            return frames
        } catch {
            reset()
            throw error
        }
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
        bufferedByteCount = 0
    }

    mutating func finish() throws {
        guard buffer.isEmpty else {
            let remaining = buffer.count
            reset()
            throw FrameDecoderError.truncatedFrame(remaining)
        }
    }

    private func decodedLengthPrefix() throws -> (length: Int, byteCount: Int)? {
        var value = 0
        let available = min(buffer.count, 5)

        for index in 0..<available {
            let byte = buffer[buffer.index(buffer.startIndex, offsetBy: index)]
            if index == 4 && (byte & 0xf0) != 0 {
                throw FrameDecoderError.malformedLength
            }
            value |= Int(byte & 0x7f) << (index * 7)
            if (byte & 0x80) == 0 {
                return (value, index + 1)
            }
        }

        if buffer.count >= 5 {
            throw FrameDecoderError.malformedLength
        }
        return nil
    }
}

enum FrameEncoder {
    static func frame(_ payload: Data) -> Data {
        var framed = Data(varint(payload.count))
        framed.append(payload)
        return framed
    }

    static func varint(_ value: Int) -> [UInt8] {
        precondition(value >= 0)
        var remaining = UInt(value)
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7f)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining != 0
        return bytes
    }
}
