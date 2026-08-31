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
