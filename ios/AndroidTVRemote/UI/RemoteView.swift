import SwiftUI

struct RemoteView: View {
    @ObservedObject var model: AppModel
    let device: RemoteDevice
    let isConnected: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

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

                commandButton("Power", systemImage: "power", command: .power)

                LazyVGrid(columns: columns, spacing: 12) {
                    Color.clear.frame(height: 56)
                    commandButton("Up", systemImage: "chevron.up", command: .up)
                    Color.clear.frame(height: 56)
                    commandButton("Left", systemImage: "chevron.left", command: .left)
                    Button("OK") { model.send(.select) }
                        .frame(minHeight: 56)
                        .disabled(!isConnected)
                    commandButton("Right", systemImage: "chevron.right", command: .right)
                    Color.clear.frame(height: 56)
                    commandButton("Down", systemImage: "chevron.down", command: .down)
                    Color.clear.frame(height: 56)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    commandButton("Back", systemImage: "chevron.backward", command: .back)
                    commandButton("Home", systemImage: "house", command: .home)
                    commandButton("Menu", systemImage: "line.3.horizontal", command: .menu)
                    commandButton("Volume Down", systemImage: "speaker.minus", command: .volumeDown)
                    commandButton("Mute", systemImage: "speaker.slash", command: .mute)
                    commandButton("Volume Up", systemImage: "speaker.plus", command: .volumeUp)
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
