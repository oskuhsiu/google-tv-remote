import AppIntents

@available(iOS 18.0, *)
extension WidgetRemoteCommand: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "TV command")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .up: DisplayRepresentation(title: "Up"),
        .down: DisplayRepresentation(title: "Down"),
        .left: DisplayRepresentation(title: "Left"),
        .right: DisplayRepresentation(title: "Right"),
        .select: DisplayRepresentation(title: "OK"),
        .back: DisplayRepresentation(title: "Back"),
        .home: DisplayRepresentation(title: "Home")
    ]

    var controlTitle: LocalizedStringResource {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "OK"
        case .back: "Back"
        case .home: "Home"
        }
    }

    var symbolName: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .select: "checkmark.circle"
        case .back: "arrow.uturn.backward"
        case .home: "house.fill"
        }
    }
}

@available(iOS 18.0, *)
struct TVCommandControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "TV command"
    static let description = IntentDescription("Choose the command for this control")

    @Parameter(title: "Command", default: .select)
    var command: WidgetRemoteCommand

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$command) to TV")
    }
}

@available(iOS 18.0, *)
struct SendWidgetRemoteCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Send TV command"
    static let description = IntentDescription("Send a command to the connected TV")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    // Applies to ControlWidget actions. Accessory widgets still follow iOS's
    // own device-authentication policy; this does not bypass that policy.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Command")
    var command: WidgetRemoteCommand

    init() {
        command = .select
    }

    init(command: WidgetRemoteCommand) {
        self.command = command
    }

    func perform() async throws -> some IntentResult {
        try Task.checkCancellation()
        // Never start pairing, bring the app forward, or enqueue offline input.
        guard WidgetRemoteBridge.loadSnapshot().isReady else {
            throw WidgetRemoteBridgeError.commandNotDelivered
        }
        let id = try WidgetRemoteBridge.enqueue(command)
        defer {
            WidgetRemoteBridge.removePendingCommand(id)
            WidgetRemoteBridge.removeAcknowledgement(id)
        }
        let wasDelivered = await WidgetRemoteBridge.waitForAcknowledgement(id)
        try Task.checkCancellation()
        if !wasDelivered {
            WidgetRemoteBridge.markUnavailable()
            throw WidgetRemoteBridgeError.commandNotDelivered
        }
        // This acknowledges acceptance by the app, not execution by the TV.
        return .result()
    }
}
