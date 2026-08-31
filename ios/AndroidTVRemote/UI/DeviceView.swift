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
                ProgressView("Looking for TVs…")
                Text("Discovery and transport integration are not available in this foundation build.")
                    .foregroundStyle(.secondary)
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
}
