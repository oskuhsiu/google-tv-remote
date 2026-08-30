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
                Button("Connect") {
                    model.connectRemembered()
                }
                Button("Forget TV", role: .destructive) {
                    model.forget()
                }
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
