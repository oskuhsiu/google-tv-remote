import SwiftUI

struct DeviceView: View {
    @ObservedObject var model: AppModel

    @State private var manualExpanded = false
    @State private var manualHost = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Connect to a TV")
                    .font(.largeTitle.bold())
                Text("Select a TV on the same Wi-Fi network.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                if let message = model.diagnosticMessage {
                    inlineMessage(message, isError: true)
                        .padding(.top, 18)
                }

                if let record = model.rememberedRecord {
                    sectionLabel("Last used")
                        .padding(.top, 28)
                    rememberedCard(record)
                        .padding(.top, 10)
                }

                sectionLabel("Nearby TVs")
                    .padding(.top, 28)
                discoveryContent
                    .padding(.top, 10)

                if model.rememberedRecord == nil {
                    manualConnectCard
                        .padding(.top, 28)
                }

                if let message = model.discoveryMessage {
                    inlineMessage(message, isError: false)
                        .padding(.top, 16)

                    Button("Retry") {
                        model.retryDiscovery()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 10)
                }

                Spacer(minLength: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func rememberedCard(_ record: LastTvRecord) -> some View {
        Button {
            guard !isConnecting else { return }
            model.connectRemembered()
        } label: {
            HStack(spacing: 14) {
                deviceIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 7) {
                        Circle()
                            .fill(isConnecting ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        Text(isConnecting ? "Connecting…" : "Ready to connect")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .contextMenu {
            Button("Forget TV", role: .destructive) {
                model.forget()
            }
            if isConnecting {
                Button("Cancel", role: .cancel) {
                    model.disconnect()
                }
            }
        }
        .disabled(!model.canConnectRemembered && !isConnecting)
    }

    @ViewBuilder
    private var discoveryContent: some View {
        if model.rememberedRecord != nil {
            HStack(spacing: 14) {
                Image(systemName: "wifi")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                Text("Forget the saved TV to discover and pair a different device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        } else if case .discovering(let candidates) = model.state, !candidates.isEmpty {
            VStack(spacing: 10) {
                ForEach(candidates) { candidate in
                    Button {
                        model.selectDiscoveredTV(candidate)
                    } label: {
                        HStack(spacing: 14) {
                            deviceIcon
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(candidate.host)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHint("Select this TV to begin pairing")
                }
            }
        } else {
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Looking for TVs nearby…")
                        .font(.subheadline.weight(.semibold))
                    Text("Make sure your TV is turned on and connected to the same Wi-Fi.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var manualConnectCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    manualExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.tint)
                    Text("Connect manually")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: manualExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if manualExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter the IP address shown in your TV network settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("192.168.1.25", text: $manualHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .textContentType(.URL)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 50)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    Button("Connect") {
                        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace }) else { return }
                        model.selectDiscoveredTV(
                            TvCandidate(
                                locatorKey: "manual:\(host)",
                                name: host,
                                host: host,
                                source: .manual
                            )
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var deviceIcon: some View {
        Image(systemName: "tv")
            .font(.title3.weight(.medium))
            .foregroundStyle(.tint)
            .frame(width: 44, height: 44)
            .background(Color.accentColor.opacity(0.14), in: Circle())
    }

    private func inlineMessage(_ message: String, isError: Bool) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isError ? Color.red.opacity(0.12) : Color(uiColor: .secondarySystemBackground)),
                in: RoundedRectangle(cornerRadius: 14)
            )
    }

    private var isConnecting: Bool {
        if case .connecting = model.state { return true }
        return false
    }
}
