import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @Binding var route: AppRoute
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsNetworkWake = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                Group {
                    if route == .compactRemote {
                        compactContent
                    } else {
                        fullContent
                    }
                }
                .frame(maxWidth: 420, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 20)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsNetworkWake) {
            NetworkWakeSettingsView(model: model)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .onChange(of: model.rememberedRecord) { previous, current in
            guard let previous, let current, current.hasSameTrust(as: previous) else {
                showsNetworkWake = false
                return
            }
        }
        .onChange(of: route) { _, destination in
            if destination == .compactRemote {
                showsNetworkWake = false
            }
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        switch model.state {
        case .needsPairing(let device), .pairing(let device):
            PairingView(model: model, device: device)
        default:
            if let record = model.rememberedRecord {
                CompactRemoteView(
                    model: model,
                    device: record.device,
                    showFullRemote: { route = .fullRemote }
                )
            } else {
                DeviceView(model: model, openNetworkWake: openNetworkWake)
            }
        }
    }

    @ViewBuilder
    private var fullContent: some View {
        switch model.state {
        case .needsPairing(let device), .pairing(let device):
            PairingView(model: model, device: device)
        case .connected(let device):
            RemoteView(
                model: model,
                device: device,
                isConnected: true,
                openCompactRemote: { route = .compactRemote },
                openNetworkWake: openNetworkWake
            )
        case .reconnecting(let device, _):
            RemoteView(
                model: model,
                device: device,
                isConnected: false,
                openCompactRemote: { route = .compactRemote },
                openNetworkWake: openNetworkWake
            )
        default:
            DeviceView(model: model, openNetworkWake: openNetworkWake)
        }
    }

    private func openNetworkWake() {
        guard model.canConnectRemembered else { return }
        showsNetworkWake = true
    }
}
