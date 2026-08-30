import Foundation

actor OutboundWriter {
    typealias Sink = @Sendable (Data) throws -> Void

    private let sink: Sink

    init(sink: @escaping Sink) {
        self.sink = sink
    }

    func send(payload: Data) throws {
        try sink(FrameEncoder.frame(payload))
    }
}
