import SwiftUI

struct CompactRemoteView: View {
    @ObservedObject var model: AppModel
    let device: RemoteDevice
    let showFullRemote: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                RemoteDPad(isEnabled: isConnected, send: model.send)
                    .frame(maxWidth: .infinity)

                RemotePressControl(
                    command: .back,
                    accessibilityLabel: "Back",
                    isEnabled: isConnected,
                    send: model.send
                ) {
                    Label("Back", systemImage: "arrow.uturn.backward")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                }

                connectionAction
                KeepReadyControl(model: model)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .navigationTitle("Remote")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Full Remote", action: showFullRemote)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var connectionAction: some View {
        if isConnecting {
            Button("Cancel", role: .cancel) { model.disconnect() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        } else if !isConnected {
            Button("Retry") { model.connectRemembered() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var isConnected: Bool {
        if case .connected = model.state { return true }
        return false
    }

    private var isConnecting: Bool {
        switch model.state {
        case .connecting, .reconnecting:
            return true
        default:
            return false
        }
    }

    private var statusText: LocalizedStringKey {
        switch model.state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting…"
        case .reconnecting:
            return "Reconnecting…"
        case .failed(_, .trustChanged, _):
            return "Security error"
        case .failed:
            return "Unavailable"
        case .disconnected:
            return "Disconnected"
        default:
            return "Unavailable"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .connected:
            return .green
        case .failed(_, .trustChanged, _):
            return .red
        case .failed:
            return .orange
        default:
            return .secondary
        }
    }
}
