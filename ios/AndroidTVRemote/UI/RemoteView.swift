import SwiftUI

struct RemoteView: View {
    @ObservedObject var model: AppModel
    let device: RemoteDevice
    let isConnected: Bool
    let openCompactRemote: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header

                VoiceIconButton(
                    state: model.voiceState,
                    isEnabled: isConnected && model.voiceState != .unavailable,
                    onStart: model.startVoice,
                    onStop: model.stopVoice
                )
                .frame(maxWidth: .infinity, alignment: .center)

                RemoteDPad(isEnabled: isConnected, send: model.send)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    commandButton("Back", systemImage: "chevron.backward", command: .back)
                    commandButton("Home", systemImage: "house.fill", command: .home)
                    actionButton("Compact Remote", systemImage: "rectangle.on.rectangle", action: openCompactRemote)
                }

                volumeControl

                if let voiceMessage = model.voiceMessage {
                    Text(voiceMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if !isConnected {
                    Button("Cancel", role: .cancel) { model.disconnect() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                KeepReadyControl(model: model)
                    .padding(.top, 2)
            }
            .padding(.vertical, 14)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Menu {
                Button {
                    model.send(.menu)
                } label: {
                    Label("Menu", systemImage: "line.3.horizontal")
                }
                .disabled(!isConnected)

                Divider()

                Button("Disconnect", role: .destructive) {
                    model.disconnect()
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(device.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(isConnected ? "Connected" : "Reconnecting…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            RemotePressControl(
                command: .power,
                accessibilityLabel: "Power",
                isEnabled: isConnected,
                send: model.send
            ) {
                Image(systemName: "power")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(width: 52, height: 52)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
            }
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 0) {
            pillCommandButton("Volume down", systemImage: "minus", command: .volumeDown)
            Divider().frame(height: 30)
            pillCommandButton("Mute", systemImage: "speaker.slash.fill", command: .mute)
            Divider().frame(height: 30)
            pillCommandButton("Volume up", systemImage: "plus", command: .volumeUp)
        }
        .frame(height: 58)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
    }

    private func commandButton(
        _ label: LocalizedStringKey,
        systemImage: String,
        command: RemoteCommand
    ) -> some View {
        RemotePressControl(
            command: command,
            accessibilityLabel: label,
            isEnabled: isConnected,
            send: model.send
        ) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func actionButton(
        _ label: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(!isConnected)
        .opacity(isConnected ? 1 : 0.4)
    }

    private func pillCommandButton(
        _ label: LocalizedStringKey,
        systemImage: String,
        command: RemoteCommand
    ) -> some View {
        RemotePressControl(
            command: command,
            accessibilityLabel: label,
            isEnabled: isConnected,
            send: model.send
        ) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct VoiceIconButton: View {
    let state: VoiceState
    let isEnabled: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var isPressed = false

    var body: some View {
        Image(systemName: state == .listening ? "waveform" : "mic.fill")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(state == .listening ? Color.white : Color.accentColor)
            .frame(width: 76, height: 76)
            .background(backgroundColor, in: Circle())
            .overlay(Circle().stroke(Color.accentColor.opacity(state == .listening ? 0.95 : 0.55), lineWidth: 1.5))
            .shadow(color: Color.accentColor.opacity(state == .listening ? 0.32 : 0.12), radius: state == .listening ? 14 : 8)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Circle())
            .onLongPressGesture(
                minimumDuration: .infinity,
                maximumDistance: 40,
                pressing: handlePress,
                perform: {}
            )
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { releaseIfNeeded() }
            }
            .onDisappear { releaseIfNeeded() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Voice search")
            .accessibilityValue(statusText)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if state == .idle { onStart() } else { onStop() }
            }
    }

    private var statusText: String {
        switch state {
        case .unavailable: "Voice not supported"
        case .idle: "Hold to talk"
        case .starting: "Starting voice…"
        case .listening: "Listening…"
        }
    }

    private var backgroundColor: Color {
        state == .listening
            ? Color.accentColor.opacity(0.72)
            : Color(uiColor: .secondarySystemBackground)
    }

    private func handlePress(_ pressing: Bool) {
        guard isEnabled else { return }
        if pressing, !isPressed {
            isPressed = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onStart()
        } else if !pressing {
            releaseIfNeeded()
        }
    }

    private func releaseIfNeeded() {
        guard isPressed else { return }
        isPressed = false
        onStop()
    }
}
