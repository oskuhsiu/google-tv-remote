import SwiftUI

@main
struct AndroidTVRemoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel

    init() {
        let identityStore = IdentityStore()
        _model = StateObject(
            wrappedValue: AppModel(
                discovery: UnavailableDiscoveryService(),
                session: AndroidTVRemoteAdapter(identityStore: identityStore),
                identity: identityStore,
                store: LastTvStore()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task {
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
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
