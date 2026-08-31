import CoreFoundation
import Foundation
import UIKit

@MainActor
final class WidgetRemoteCommandListener {
    var onCommand: ((WidgetRemoteCommand) -> Bool)? {
        didSet { drainPendingCommands() }
    }
    var snapshotProvider: (() -> WidgetRemoteSnapshot?)? {
        didSet { startHeartbeat() }
    }
    private var terminationObserver: NSObjectProtocol?
    private var heartbeatTask: Task<Void, Never>?

    init() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            widgetRemoteCommandCallback,
            WidgetRemoteBridge.notificationName.rawValue,
            nil,
            .deliverImmediately
        )
        terminationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            WidgetRemoteBridge.markUnavailable()
        }
    }

    deinit {
        heartbeatTask?.cancel()
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            WidgetRemoteBridge.notificationName,
            nil
        )
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func drainPendingCommands() {
        WidgetRemoteBridge.takePendingCommands().forEach { pending in
            guard onCommand?(pending.command) == true else { return }
            try? WidgetRemoteBridge.acknowledge(pending.id)
            scheduleAcknowledgementCleanup(pending.id)
            if let snapshot = snapshotProvider?() {
                WidgetRemoteBridge.saveSnapshot(snapshot)
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(WidgetRemoteBridge.heartbeatInterval * 1_000_000_000)
                    )
                } catch {
                    return
                }
                guard let snapshot = self?.snapshotProvider?(),
                      snapshot.availability == .ready else {
                    continue
                }
                WidgetRemoteBridge.saveSnapshot(snapshot)
            }
        }
    }

    private func scheduleAcknowledgementCleanup(_ id: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            WidgetRemoteBridge.removeAcknowledgement(id)
        }
    }
}

private let widgetRemoteCommandCallback: CFNotificationCallback = {
    _, observer, _, _, _ in
    guard let observer else { return }
    let listener = Unmanaged<WidgetRemoteCommandListener>
        .fromOpaque(observer)
        .takeUnretainedValue()
    Task { @MainActor in
        listener.drainPendingCommands()
    }
}
