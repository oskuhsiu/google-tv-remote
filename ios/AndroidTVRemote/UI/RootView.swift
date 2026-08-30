import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .needsPairing(let device), .pairing(let device):
                    PairingView(device: device)
                case .connected(let device):
                    RemoteView(model: model, device: device, isConnected: true)
                case .reconnecting(let device, _):
                    RemoteView(model: model, device: device, isConnected: false)
                default:
                    DeviceView(model: model)
                }
            }
            .frame(maxWidth: 420)
            .padding()
        }
    }
}
