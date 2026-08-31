import SwiftUI

struct KeepReadyControl: View {
    @ObservedObject var model: AppModel
    @State private var showsDisclosure = false

    var body: some View {
        if model.keepReadyAvailable {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Keep Ready", isOn: binding)
                    .font(.headline)
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(statusColor)
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .alert("Keep Remote Ready?", isPresented: $showsDisclosure) {
                Button("Cancel", role: .cancel) {}
                Button("Enable") { model.setKeepReadyEnabled(true) }
            } message: {
                Text("This uses silent background audio to keep the TV connection ready. It may use more battery and is experimental.")
            }
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { model.keepReadyEnabled },
            set: { enabled in
                if enabled {
                    showsDisclosure = true
                } else {
                    model.setKeepReadyEnabled(false)
                }
            }
        )
    }

    private var statusText: LocalizedStringKey {
        guard model.keepReadyEnabled else { return "Off" }
        switch model.keepAliveStatus {
        case .off, .ready:
            return "On"
        case .starting:
            return "Starting…"
        case .interrupted:
            return "Interrupted"
        }
    }

    private var statusColor: Color {
        model.keepAliveStatus == .interrupted ? .orange : .secondary
    }
}
