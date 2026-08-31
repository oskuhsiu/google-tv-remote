import CoreFoundation
import Foundation
import WidgetKit

enum WidgetRemoteAvailability: String, Codable, Sendable {
    case ready
    case connecting
    case unavailable
}

struct WidgetRemoteSnapshot: Codable, Equatable, Sendable {
    let tvName: String?
    let availability: WidgetRemoteAvailability
    let confirmedAt: Date

    static let unavailable = WidgetRemoteSnapshot(
        tvName: nil,
        availability: .unavailable
    )

    init(
        tvName: String?,
        availability: WidgetRemoteAvailability,
        confirmedAt: Date = Date()
    ) {
        self.tvName = tvName
        self.availability = availability
        self.confirmedAt = confirmedAt
    }

    var isReady: Bool {
        availability == .ready
    }

    var leaseExpiration: Date? {
        switch availability {
        case .ready, .connecting:
            confirmedAt.addingTimeInterval(WidgetRemoteBridge.leaseDuration)
        case .unavailable:
            nil
        }
    }

    func unavailable(at date: Date = Date()) -> WidgetRemoteSnapshot {
        WidgetRemoteSnapshot(tvName: tvName, availability: .unavailable, confirmedAt: date)
    }

    func validated(at date: Date) -> WidgetRemoteSnapshot {
        guard let expiration = leaseExpiration, date >= expiration else { return self }
        return unavailable(at: expiration)
    }
}

enum WidgetRemoteCommand: String, Codable, CaseIterable, Sendable {
    case up
    case down
    case left
    case right
    case select
    case back
    case home
}

struct PendingWidgetRemoteCommand: Sendable {
    let id: UUID
    let command: WidgetRemoteCommand
}

enum WidgetRemoteBridgeError: LocalizedError {
    case appGroupUnavailable
    case commandNotDelivered

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            String(localized: "The TV remote is unavailable. Open the app and try again.")
        case .commandNotDelivered:
            String(localized: "The TV is not connected. Open the app to reconnect.")
        }
    }
}

enum WidgetRemoteBridge {
    static let heartbeatInterval: TimeInterval = 60
    static let leaseDuration: TimeInterval = 5 * 60
    static let appGroupIdentifier = "group.dev.local.AndroidTVRemote"
    static let widgetKind = "dev.local.AndroidTVRemote.homeRemote"
    static let notificationName = CFNotificationName(
        "dev.local.AndroidTVRemote.widgetCommand" as CFString
    )

    private static let snapshotKey = "widgetRemoteSnapshot"
    private static let commandsDirectoryName = "WidgetRemoteCommands"

    static func loadSnapshot(at date: Date = Date()) -> WidgetRemoteSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetRemoteSnapshot.self, from: data) else {
            return .unavailable
        }
        return snapshot.validated(at: date)
    }

    static func saveSnapshot(_ snapshot: WidgetRemoteSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot),
              data != defaults.data(forKey: snapshotKey) else {
            return
        }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    @discardableResult
    static func enqueue(_ command: WidgetRemoteCommand) throws -> UUID {
        let directory = try commandsDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let id = UUID()
        let envelope = WidgetRemoteCommandEnvelope(id: id, command: command, createdAt: Date())
        let stagingURL = directory.appendingPathComponent("\(id.uuidString).writing")
        let fileURL = directory.appendingPathComponent("\(id.uuidString).json")
        try JSONEncoder().encode(envelope).write(to: stagingURL)
        try FileManager.default.moveItem(at: stagingURL, to: fileURL)

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        return id
    }

    static func takePendingCommands(maxAge: TimeInterval = 3) -> [PendingWidgetRemoteCommand] {
        guard let directory = try? commandsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else {
            return []
        }

        let now = Date()
        let envelopes = files
            .filter { $0.pathExtension == "json" }
            .compactMap { fileURL -> WidgetRemoteCommandEnvelope? in
                defer { try? FileManager.default.removeItem(at: fileURL) }
                guard let data = try? Data(contentsOf: fileURL),
                      let envelope = try? JSONDecoder().decode(
                          WidgetRemoteCommandEnvelope.self,
                          from: data
                      ),
                      now.timeIntervalSince(envelope.createdAt) <= maxAge else {
                    return nil
                }
                return envelope
            }

        return envelopes
            .sorted { $0.createdAt < $1.createdAt }
            .map { PendingWidgetRemoteCommand(id: $0.id, command: $0.command) }
    }

    static func acknowledge(_ id: UUID) throws {
        let directory = try commandsDirectory()
        let stagingURL = directory.appendingPathComponent("\(id.uuidString).ack-writing")
        let acknowledgementURL = directory.appendingPathComponent("\(id.uuidString).ack")
        try Data().write(to: stagingURL)
        try FileManager.default.moveItem(at: stagingURL, to: acknowledgementURL)
    }

    static func waitForAcknowledgement(
        _ id: UUID,
        timeout: TimeInterval = 1
    ) async -> Bool {
        guard let directory = try? commandsDirectory() else { return false }
        let acknowledgementURL = directory.appendingPathComponent("\(id.uuidString).ack")
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if FileManager.default.fileExists(atPath: acknowledgementURL.path) {
                try? FileManager.default.removeItem(at: acknowledgementURL)
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while !Task.isCancelled && Date() < deadline

        return false
    }

    static func removePendingCommand(_ id: UUID) {
        guard let directory = try? commandsDirectory() else { return }
        ["json", "writing"].forEach { pathExtension in
            let fileURL = directory.appendingPathComponent(
                "\(id.uuidString).\(pathExtension)"
            )
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static func removeAcknowledgement(_ id: UUID) {
        guard let directory = try? commandsDirectory() else { return }
        ["ack", "ack-writing"].forEach { pathExtension in
            let fileURL = directory.appendingPathComponent(
                "\(id.uuidString).\(pathExtension)"
            )
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static func markUnavailable() {
        let current = loadSnapshot()
        saveSnapshot(current.unavailable())
    }

    private static func commandsDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw WidgetRemoteBridgeError.appGroupUnavailable
        }
        return container.appendingPathComponent(commandsDirectoryName, isDirectory: true)
    }
}

private struct WidgetRemoteCommandEnvelope: Codable {
    let id: UUID
    let command: WidgetRemoteCommand
    let createdAt: Date
}
