import SwiftUI

@main
struct AndroidTVRemoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @State private var route: AppRoute = .fullRemote
    private let widgetCommandListener: WidgetRemoteCommandListener
    private let showsWidgetPreview: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let showsWidgetPreview = arguments.contains("--widget-preview")
        self.showsWidgetPreview = showsWidgetPreview
        let widgetCommandListener = WidgetRemoteCommandListener()
        self.widgetCommandListener = widgetCommandListener
#if DEBUG
        if arguments.contains("--compact-preview") || showsWidgetPreview {
            let record = DebugCompactPreview.record
            let model = AppModel(
                discovery: UnavailableDiscoveryService(),
                session: DebugCompactPreview.Session(),
                identity: DebugCompactPreview.Identity(),
                store: DebugCompactPreview.Store(record: record),
                backgroundKeepAlive: BackgroundKeepAliveController()
            )
            widgetCommandListener.snapshotProvider = { [weak model] in model?.widgetSnapshot }
            widgetCommandListener.onCommand = { [weak model] command in
                model?.sendWidgetCommand(command) ?? false
            }
            _model = StateObject(wrappedValue: model)
            _route = State(initialValue: .compactRemote)
            return
        }
#endif
        let identityStore = IdentityStore()
        let defaults = UserDefaults.standard
        let model = AppModel(
            discovery: UnavailableDiscoveryService(),
            session: AndroidTVRemoteAdapter(identityStore: identityStore),
            identity: identityStore,
            store: LastTvStore(),
            backgroundKeepAlive: BackgroundKeepAliveController(),
            initialKeepReadyEnabled: defaults.bool(forKey: "keepReadyEnabled"),
            persistKeepReady: { enabled in
                defaults.set(enabled, forKey: "keepReadyEnabled")
            }
        )
        widgetCommandListener.snapshotProvider = { [weak model] in model?.widgetSnapshot }
        widgetCommandListener.onCommand = { [weak model] command in
            model?.sendWidgetCommand(command) ?? false
        }
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if showsWidgetPreview {
                    DebugWidgetPreviewView()
                } else {
                    RootView(model: model, route: $route)
                }
#else
                RootView(model: model, route: $route)
#endif
            }
                .task {
                    WidgetRemoteBridge.saveSnapshot(model.widgetSnapshot)
                    if scenePhase == .active {
                        model.enterForeground()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.enterForeground()
                    case .background:
                        model.enterBackground()
                    case .inactive:
                        model.enterInactive()
                    @unknown default:
                        break
                    }
                }
                .onOpenURL { url in
                    guard let destination = AppRoute(url: url) else { return }
                    route = destination
                    if destination == .compactRemote {
                        model.requestCompactRemote()
                    }
                }
                .onChange(of: model.state) { _, _ in
                    WidgetRemoteBridge.saveSnapshot(model.widgetSnapshot)
                }
                .onChange(of: model.rememberedRecord) { _, _ in
                    WidgetRemoteBridge.saveSnapshot(model.widgetSnapshot)
                }
                .onChange(of: model.keepReadyEnabled) { _, _ in
                    WidgetRemoteBridge.saveSnapshot(model.widgetSnapshot)
                }
                .onChange(of: model.keepAliveStatus) { _, _ in
                    WidgetRemoteBridge.saveSnapshot(model.widgetSnapshot)
                }
        }
    }
}
