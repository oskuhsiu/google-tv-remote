import SwiftUI

struct RemoteView: View {
    @ObservedObject var model: AppModel
    let device: RemoteDevice
    let isConnected: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name).font(.headline)
                        Text(isConnected ? "Connected" : "Reconnecting…")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect") { model.disconnect() }
                }

                Text("Transport diagnostic")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                commandButton("Up", systemImage: "chevron.up", command: .up)
                Button("OK") { model.send(.select) }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .disabled(!isConnected)

                HStack(spacing: 12) {
                    commandButton("Back", systemImage: "chevron.backward", command: .back)
                    commandButton("Home", systemImage: "house", command: .home)
                }
            }
        }
        .navigationTitle("Remote")
    }

    private func commandButton(
        _ label: String,
        systemImage: String,
        command: RemoteCommand
    ) -> some View {
        Button {
            model.send(command)
        } label: {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .accessibilityLabel(label)
        .disabled(!isConnected)
    }
}
