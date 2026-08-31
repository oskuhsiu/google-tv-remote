import AppIntents

@available(iOS 18.0, *)
enum RemoteIntentDestination: String, AppEnum, URLRepresentableEnum {
    case compact

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Remote")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .compact: DisplayRepresentation(title: "Remote")
    ]
    static var urlRepresentation: EnumURLRepresentation<Self> {
        let compactURL: EnumURLRepresentation<Self>.EnumSingleURLRepresentation =
            "androidtvremote://compact"
        return EnumURLRepresentation([.compact: compactURL])
    }
}

@available(iOS 18.0, *)
struct OpenCompactRemoteIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open compact remote"
    static let description = IntentDescription("Open the compact TV remote")

    @Parameter(title: "Remote")
    var target: RemoteIntentDestination

    init() {
        target = .compact
    }

    init(target: RemoteIntentDestination) {
        self.target = target
    }
}
