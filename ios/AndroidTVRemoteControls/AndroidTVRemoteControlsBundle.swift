import SwiftUI
import WidgetKit

@main
@available(iOSApplicationExtension 18.0, *)
struct AndroidTVRemoteControlsBundle: WidgetBundle {
    var body: some Widget {
        RemoteControl()
        RemoteWidget()
    }
}
