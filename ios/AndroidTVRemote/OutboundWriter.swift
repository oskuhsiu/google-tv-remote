import Foundation

final class OutboundWriter: @unchecked Sendable {
    typealias Sink = @Sendable (Data) throws -> Void

    private let queue = DispatchQueue(label: "remote.outbound.writer")
    private let sink: Sink

    init(sink: @escaping Sink) {
        self.sink = sink
    }

    func send(payload: Data) throws {
        try queue.sync {
            try sink(FrameEncoder.frame(payload))
        }
    }
}
