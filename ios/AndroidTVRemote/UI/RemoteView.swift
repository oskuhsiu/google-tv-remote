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

                RemoteDPad(isEnabled: isConnected, send: model.send)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    commandButton("Back", systemImage: "chevron.backward", command: .back)
                    commandButton("Home", systemImage: "house", command: .home)
                }

                VoiceHoldButton(
                    state: model.voiceState,
                    isEnabled: isConnected && model.voiceState != .unavailable,
                    onStart: model.startVoice,
                    onStop: model.stopVoice
                )

                if let voiceMessage = model.voiceMessage {
                    Text(voiceMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !isConnected {
                    Button("Cancel", role: .cancel) { model.disconnect() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                KeepReadyControl(model: model)
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

private struct VoiceHoldButton: View {
    let state: VoiceState
    let isEnabled: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state == .listening ? "waveform" : "mic.fill")
                .font(.title2)
            Text(statusText)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18))
        .opacity(isEnabled ? 1 : 0.55)
        .contentShape(RoundedRectangle(cornerRadius: 18))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice search")
        .accessibilityValue(statusText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if state == .idle {
                onStart()
            } else {
                onStop()
            }
        }
    }

    private var statusText: String {
        switch state {
        case .unavailable:
            return "Voice not supported"
        case .idle:
            return "Hold to talk"
        case .starting:
            return "Starting voice…"
        case .listening:
            return "Listening…"
        }
    }

    private var backgroundColor: Color {
        state == .listening
            ? Color.accentColor.opacity(0.22)
            : Color(uiColor: .secondarySystemBackground)
    }

    private func handlePress(_ pressing: Bool) {
        guard isEnabled else { return }
        if pressing, !isPressed {
            isPressed = true
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
