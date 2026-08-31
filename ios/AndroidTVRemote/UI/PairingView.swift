import SwiftUI

struct PairingView: View {
    @ObservedObject var model: AppModel
    let device: RemoteDevice
    @State private var code = ""

    var body: some View {
        Form {
            Section("Pair with \(device.name)") {
                TextField("6-character code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                Button("Submit") {
                    model.submitPairingCode(code)
                }
                    .disabled(!PairingCodeValidator.isValid(code) || isSubmitting)
                if isSubmitting {
                    ProgressView("Connecting…")
                } else {
                    Text("Enter the 6-character code shown on your TV.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Button("Back to TVs", role: .cancel) {
                    model.cancelPairing()
                }
            }
        }
        .navigationTitle("Pair TV")
    }

    private var isSubmitting: Bool {
        if case .pairing = model.state { return true }
        return false
    }
}
