import SwiftUI

struct PairingView: View {
    let device: RemoteDevice
    @State private var code = ""

    var body: some View {
        Form {
            Section("Pair with \(device.name)") {
                TextField("6-character code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Submit") {}
                    .disabled(true)
                Text("Pairing transport integration is not available in this foundation build.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pair TV")
    }
}

