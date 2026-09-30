import SwiftUI

struct NetworkWakeSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var macAddress = ""
    @State private var guideExpanded = false
    @State private var showsMACValidationError = false
    @FocusState private var macIsFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "tv")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.rememberedRecord?.name ?? "TV")
                                .font(.title2.bold())
                            Text("Test waking your TV from standby over the local network.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("MAC address")
                            .font(.headline)
                        HStack {
                            TextField("A4:77:33:12:AB:CD", text: $macAddress)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .submitLabel(.done)
                                .focused($macIsFocused)
                                .onSubmit { macIsFocused = false }
                                .onChange(of: macAddress) { _, _ in showsMACValidationError = false }
                                .accessibilityLabel("MAC address")
                                .accessibilityIdentifier("network-wake-mac")
                            if !macAddress.isEmpty {
                                Button { macAddress = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Clear input")
                            }
                        }
                        .padding(12)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        if showsMACValidationError {
                            Text("Enter a valid device MAC address, such as A4:77:33:12:AB:CD.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("network-wake-mac-error")
                        }
                        Text("Use the MAC address for the TV's current Wi-Fi or Ethernet connection.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .wakeCard()

                    Label(status, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wakeCard()

                    DisclosureGroup("How to find the MAC address", isExpanded: $guideExpanded) {
                        NetworkWakeGuideView()
                            .padding(.top, 14)
                    }
                    .font(.headline)
                    .wakeCard()
                    .accessibilityIdentifier("network-wake-guide")
                    .onChange(of: guideExpanded) { _, expanded in
                        if expanded { macIsFocused = false }
                    }

                    Text("Keep the TV plugged in and in standby. Enable Network Standby or Remote Start if your TV offers it. Wake support varies by model.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        Button {
                            macIsFocused = false
                            model.testNetworkWake()
                        } label: {
                            HStack(spacing: 10) {
                                if model.isTestingNetworkWake {
                                    ProgressView()
                                } else {
                                    Image(systemName: "power")
                                }
                                Text("Test Wake")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!canTest || model.isTestingNetworkWake)
                        .accessibilityIdentifier("network-wake-test")
                        Text("First put the TV in standby with its physical remote. Keep your iPhone on the same local network.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if !canTest, !macAddress.isEmpty {
                            Text("Save the MAC address before testing.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let message = model.networkWakeMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .wakeCard()
                            .accessibilityIdentifier("network-wake-feedback")
                    }

                    if model.rememberedRecord?.networkWake != nil {
                        Button("Clear MAC address", role: .destructive) {
                            if model.clearNetworkWakeMAC() { macAddress = "" }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("network-wake-clear")
                    }
                }
                .frame(maxWidth: 420)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Network Wake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        macIsFocused = false
                        guard WolPacket.normalizedMAC(macAddress) != nil else {
                            showsMACValidationError = true
                            return
                        }
                        if model.saveNetworkWakeMAC(macAddress) {
                            macAddress = model.rememberedRecord?.networkWake?.macAddress ?? ""
                        }
                    }
                    .disabled(macAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isTestingNetworkWake)
                    .accessibilityIdentifier("network-wake-save")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.blue)
        .onAppear { macAddress = model.rememberedRecord?.networkWake?.macAddress ?? "" }
        .onDisappear { model.cancelNetworkWakeTest() }
    }

    private var canTest: Bool {
        guard model.canConnectRemembered, let saved = model.rememberedRecord?.networkWake else { return false }
        return WolPacket.normalizedMAC(macAddress) == saved.macAddress
    }

    private var status: LocalizedStringKey {
        switch model.rememberedRecord?.networkWake?.capability {
        case .verified: "Wake support previously confirmed"
        case .unsupported: "Wake support marked as unavailable"
        case .unverified: "Wake support not confirmed"
        case nil: "No MAC address saved"
        }
    }
}

struct NetworkWakeGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            step(1, "Open Settings or Help on your TV.")
            step(2, "Look for About, Status, or Network status.")
            step(3, "Find the MAC address and enter it above.")
            Text("For Wi-Fi, use the Wi-Fi MAC. For a network cable, use the Ethernet MAC.")
                .foregroundStyle(.secondary)
            Divider()
            Text("Examples (menus vary by model)")
                .font(.subheadline.weight(.semibold))
            Text("Google TV Streamer / Chromecast: Settings → System → About → Status")
            Text("TCL: Settings → Network & Internet → current network")
            Text("Sony: Help → Status & Diagnostics → Network status")
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number))
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(Color(uiColor: .tertiarySystemBackground), in: Circle())
            Text(text)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        }
    }
}

private extension View {
    func wakeCard() -> some View {
        padding(16)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
