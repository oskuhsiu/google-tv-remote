import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct RemoteControl: ControlWidget {
    static let kind = "dev.local.AndroidTVRemote.compactRemote"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenCompactRemoteIntent()) {
                Label("Remote", systemImage: "av.remote.fill")
                    .accessibilityLabel("Remote")
                    .accessibilityHint("Opens compact TV remote")
            }
        }
        .displayName("Remote")
        .description("Open the compact TV remote")
    }
}

/// A direct action, unlike the existing Remote control which opens the app.
@available(iOSApplicationExtension 18.0, *)
struct TVCommandControl: ControlWidget {
    static let kind = "dev.local.AndroidTVRemote.tvCommand"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: TVCommandValueProvider()) { command in
            ControlWidgetButton(action: SendWidgetRemoteCommandIntent(command: command)) {
                Label {
                    Text(command.controlTitle)
                } icon: {
                    Image(systemName: command.symbolName)
                }
            }
        }
        .displayName("TV Command")
        .description("Send a TV command without opening the app. Connect and enable Keep Ready first.")
        .promptsForUserConfiguration()
    }
}

@available(iOSApplicationExtension 18.0, *)
private struct TVCommandValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: TVCommandControlConfiguration) -> WidgetRemoteCommand {
        configuration.command
    }

    func currentValue(configuration: TVCommandControlConfiguration) async throws -> WidgetRemoteCommand {
        // Read live availability in perform(), not a cached control rendering.
        configuration.command
    }
}
