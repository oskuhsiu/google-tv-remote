import SwiftUI

struct DeviceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Android TV Remote")
                .font(.largeTitle.bold())

            if let record = model.rememberedRecord {
                Text(record.name).font(.headline)
                Text("Remembered TV")
                    .foregroundStyle(.secondary)
                if case .connecting = model.state {
                    ProgressView("Connecting…")
                    Button("Cancel", role: .cancel) {
                        model.disconnect()
                    }
                } else {
                    Button("Connect") {
                        model.connectRemembered()
                    }
                    .disabled(!model.canConnectRemembered)
                }
                Button("Forget TV", role: .destructive) {
                    model.forget()
                }
                KeepReadyControl(model: model)
            } else {
                discoveryContent
                if let message = model.discoveryMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        model.retryDiscovery()
                    }
                }
            }

            if let message = model.diagnosticMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var discoveryContent: some View {
        if case .discovering(let candidates) = model.state, !candidates.isEmpty {
            Text("Nearby TVs")
                .font(.headline)
            ForEach(candidates) { candidate in
                Button {
                    model.selectDiscoveredTV(candidate)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tv")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                                .font(.body.weight(.medium))
                            Text(candidate.host)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .buttonStyle(.plain)
                .accessibilityHint("Select this TV to begin pairing")
            }
        } else {
            ProgressView("Looking for TVs…")
            Text("Make sure the TV and iPhone are on the same local network.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
