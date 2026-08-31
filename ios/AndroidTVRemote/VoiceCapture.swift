import AVFoundation
import Foundation

enum MicrophonePermission {
    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

final class VoiceCapture: @unchecked Sendable {
    static let sampleRate: Double = 8_000
    static let chunkByteCount = 8_192

    private let audioSession: AVAudioSession
    private let engine: AVAudioEngine
    private let stateLock = NSLock()

    private var converter: AVAudioConverter?
    private var chunker = VoicePCMChunker(chunkByteCount: chunkByteCount)
    private var onChunk: (@Sendable (Data) -> Void)?
    private var onFailure: (@Sendable (Error) -> Void)?
    private var isRunning = false
    private var tapInstalled = false

    init(
        audioSession: AVAudioSession = .sharedInstance(),
        engine: AVAudioEngine = AVAudioEngine()
    ) {
        self.audioSession = audioSession
        self.engine = engine
    }

    func start(
        onChunk: @escaping @Sendable (Data) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws {
        stateLock.lock()
        let alreadyRunning = isRunning
        stateLock.unlock()
        guard !alreadyRunning else { throw VoiceCaptureError.alreadyRunning }

        try audioSession.setCategory(.record, mode: .measurement)
        try? audioSession.setPreferredSampleRate(Self.sampleRate)
        try audioSession.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            deactivateAudioSession()
            throw VoiceCaptureError.inputUnavailable
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            deactivateAudioSession()
            throw VoiceCaptureError.converterUnavailable
        }

        stateLock.lock()
        self.converter = converter
        chunker = VoicePCMChunker(chunkByteCount: Self.chunkByteCount)
        self.onChunk = onChunk
        self.onFailure = onFailure
        isRunning = true
        stateLock.unlock()

        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.consume(buffer, outputFormat: outputFormat)
        }
        tapInstalled = true
        engine.prepare()

        do {
            try engine.start()
        } catch {
            _ = stop()
            throw error
        }
    }

    /// Stops recording and returns one zero-padded final packet, when needed.
    func stop() -> Data? {
        stateLock.lock()
        let wasRunning = isRunning
        isRunning = false
        stateLock.unlock()

        if wasRunning || engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        stateLock.lock()
        let finalChunk = chunker.finish()
        converter = nil
        onChunk = nil
        onFailure = nil
        stateLock.unlock()

        deactivateAudioSession()
        return finalChunk
    }

    private func consume(_ inputBuffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
        var producedChunks: [Data] = []
        var failure: Error?
        var chunkHandler: (@Sendable (Data) -> Void)?
        var failureHandler: (@Sendable (Error) -> Void)?

        stateLock.lock()
        if isRunning, let converter {
            do {
                let rateRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
                let capacity = max(
                    1,
                    AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * rateRatio)) + 32
                )
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: capacity
                ) else {
                    throw VoiceCaptureError.outputBufferUnavailable
                }

                var suppliedInput = false
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) {
                    _, inputStatus in
                    guard !suppliedInput else {
                        inputStatus.pointee = .noDataNow
                        return nil
                    }
                    suppliedInput = true
                    inputStatus.pointee = .haveData
                    return inputBuffer
                }
                if status == .error {
                    throw conversionError ?? VoiceCaptureError.conversionFailed
                }

                if outputBuffer.frameLength > 0 {
                    guard let samples = outputBuffer.int16ChannelData?.pointee else {
                        throw VoiceCaptureError.outputBufferUnavailable
                    }
                    let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
                    producedChunks = chunker.append(Data(bytes: samples, count: byteCount))
                }
                chunkHandler = onChunk
            } catch {
                isRunning = false
                failure = error
                failureHandler = onFailure
            }
        }
        stateLock.unlock()

        producedChunks.forEach { chunkHandler?($0) }
        if let failure {
            failureHandler?(failure)
        }
    }

    private func deactivateAudioSession() {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private enum VoiceCaptureError: Error {
    case alreadyRunning
    case inputUnavailable
    case converterUnavailable
    case outputBufferUnavailable
    case conversionFailed
}

private struct VoicePCMChunker {
    let chunkByteCount: Int
    private var pending = Data()

    init(chunkByteCount: Int) {
        precondition(chunkByteCount > 0)
        self.chunkByteCount = chunkByteCount
    }

    mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var chunks: [Data] = []
        while pending.count >= chunkByteCount {
            chunks.append(Data(pending.prefix(chunkByteCount)))
            pending.removeFirst(chunkByteCount)
        }
        return chunks
    }

    mutating func finish() -> Data? {
        guard !pending.isEmpty else { return nil }
        pending.append(Data(count: chunkByteCount - pending.count))
        defer { pending.removeAll(keepingCapacity: false) }
        return pending
    }
}
