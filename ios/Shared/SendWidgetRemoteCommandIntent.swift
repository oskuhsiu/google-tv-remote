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
}

@available(iOS 18.0, *)
struct SendWidgetRemoteCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Send TV command"
    static let description = IntentDescription("Send a command to the connected TV")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Command")
    var command: WidgetRemoteCommand

    init() {
        command = .select
    }

    init(command: WidgetRemoteCommand) {
        self.command = command
    }

    func perform() async throws -> some IntentResult {
        let id = try WidgetRemoteBridge.enqueue(command)
        let wasDelivered = await WidgetRemoteBridge.waitForAcknowledgement(id)
        if !wasDelivered {
            WidgetRemoteBridge.removePendingCommand(id)
            WidgetRemoteBridge.markUnavailable()
            throw WidgetRemoteBridgeError.commandNotDelivered
        }
        return .result()
    }
}
