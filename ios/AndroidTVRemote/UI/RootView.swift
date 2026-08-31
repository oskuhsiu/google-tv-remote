import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @Binding var route: AppRoute

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
                DeviceView(model: model)
            }
        }
    }

    @ViewBuilder
    private var fullContent: some View {
        switch model.state {
        case .needsPairing(let device), .pairing(let device):
            PairingView(model: model, device: device)
        case .connected(let device):
            RemoteView(model: model, device: device, isConnected: true)
        case .reconnecting(let device, _):
            RemoteView(model: model, device: device, isConnected: false)
        default:
            DeviceView(model: model)
        }
    }
}
