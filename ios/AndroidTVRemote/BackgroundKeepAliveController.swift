import AVFoundation
import Foundation

@MainActor
final class BackgroundKeepAliveController: BackgroundKeepAliveControlling {
    var isAvailable: Bool {
#if BACKGROUND_KEEPALIVE_EXPERIMENTAL
        true
#else
        false
#endif
    }

    private(set) var status: KeepAliveStatus = .off {
        didSet {
            guard status != oldValue else { return }
            onStatusChanged?(status)
        }
    }

    var onStatusChanged: ((KeepAliveStatus) -> Void)?

    private let audioSession: AVAudioSession
    private var player: AVAudioPlayer?
    private var shouldRun = false
    private var observers: [NSObjectProtocol] = []

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
        observeAudioSession()
    }

    func start() {
        shouldRun = true
#if BACKGROUND_KEEPALIVE_EXPERIMENTAL
        guard status != .ready || player?.isPlaying != true else { return }
        startPlayback()
#else
        status = .off
#endif
    }

    func stop() {
        shouldRun = false
        player?.stop()
        player = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        status = .off
    }

    private func startPlayback() {
        status = .starting
        do {
            try audioSession.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try audioSession.setActive(true)

            let player = try AVAudioPlayer(data: Self.silentWaveData)
            player.numberOfLoops = -1
            player.volume = 1
            player.prepareToPlay()
            guard player.play() else {
                throw KeepAliveError.playbackDidNotStart
            }
            self.player = player
            status = .ready
        } catch {
            player = nil
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            status = .interrupted
        }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleInterruption(notification)
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.recoverPlaybackIfNeeded()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.player = nil
                    self.status = self.shouldRun ? .interrupted : .off
                    self.recoverPlaybackIfNeeded()
                }
            }
        )
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            if shouldRun { status = .interrupted }
        case .ended:
            recoverPlaybackIfNeeded()
        @unknown default:
            if shouldRun { status = .interrupted }
        }
    }

    private func recoverPlaybackIfNeeded() {
        guard shouldRun, player?.isPlaying != true else { return }
        startPlayback()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private enum KeepAliveError: Error {
        case playbackDidNotStart
    }

    /// One second of mono 8 kHz, signed 16-bit PCM silence in a WAV container.
    private static let silentWaveData: Data = {
        let sampleRate: UInt32 = 8_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleCount = sampleRate
        let dataSize = sampleCount * UInt32(channels) * UInt32(bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + dataSize)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channels)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.appendASCII("data")
        data.appendLittleEndian(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }()
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

@MainActor
final class DisabledBackgroundKeepAliveController: BackgroundKeepAliveControlling {
    let isAvailable = false
    private(set) var status: KeepAliveStatus = .off
    var onStatusChanged: ((KeepAliveStatus) -> Void)?

    func start() {}
    func stop() {
        status = .off
        onStatusChanged?(.off)
    }
}
