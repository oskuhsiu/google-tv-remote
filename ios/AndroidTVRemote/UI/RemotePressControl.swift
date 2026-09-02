import SwiftUI
import UIKit

struct RemotePressControl<Label: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let command: RemoteCommand
    let accessibilityLabel: LocalizedStringKey
    let isEnabled: Bool
    let send: (RemoteCommand, RemoteKeyAction) -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false
    @State private var didStartLongPress = false
    @State private var pressTask: Task<Void, Never>?

    var body: some View {
        label()
            .contentShape(Rectangle())
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? (isPressed ? 0.72 : 1) : 0.38)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginPressIfNeeded() }
                    .onEnded { _ in endPress() },
                including: isEnabled ? .all : .none
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .disabled(!isEnabled)
            .accessibilityAction {
                guard isEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                send(command, .short)
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { cancelPress() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelPress() }
            }
            .onDisappear { cancelPress() }
    }

    private func beginPressIfNeeded() {
        guard isEnabled, !isPressed else { return }
        isPressed = true
        didStartLongPress = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        switch RemotePressPolicy.behavior(for: command) {
        case .single:
            send(command, .short)
        case .repeatWhileHeld:
            send(command, .short)
            pressTask = Task { @MainActor in
                do {
                    try await sleep(RemotePressPolicy.repeatDelay)
                    while !Task.isCancelled, isPressed {
                        send(command, .short)
                        try await sleep(RemotePressPolicy.repeatInterval)
                    }
                } catch {}
            }
        case .longPress:
            pressTask = Task { @MainActor in
                do {
                    try await sleep(RemotePressPolicy.longPressThreshold)
                    guard !Task.isCancelled, isPressed else { return }
                    didStartLongPress = true
                    send(command, .startLong)
                } catch {}
            }
        }
    }

    private func endPress() {
        guard isPressed else { return }
        let behavior = RemotePressPolicy.behavior(for: command)
        let hadLongPress = didStartLongPress
        pressTask?.cancel()
        pressTask = nil
        isPressed = false
        didStartLongPress = false

        if behavior == .longPress {
            send(command, hadLongPress ? .endLong : .short)
        }
    }

    private func cancelPress() {
        guard isPressed else { return }
        let shouldEndLongPress = didStartLongPress
        pressTask?.cancel()
        pressTask = nil
        isPressed = false
        didStartLongPress = false
        if shouldEndLongPress {
            send(command, .endLong)
        }
    }

    private func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

struct RemoteDPad: View {
    let isEnabled: Bool
    let send: (RemoteCommand, RemoteKeyAction) -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemBackground))
            Circle()
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.2)

            direction(.up, label: "Up", symbol: "chevron.up", x: 0, y: -88)
            direction(.down, label: "Down", symbol: "chevron.down", x: 0, y: 88)
            direction(.left, label: "Left", symbol: "chevron.left", x: -88, y: 0)
            direction(.right, label: "Right", symbol: "chevron.right", x: 88, y: 0)

            RemotePressControl(
                command: .select,
                accessibilityLabel: "OK",
                isEnabled: isEnabled,
                send: send
            ) {
                Text("OK")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 82, height: 82)
                    .background(Color(uiColor: .tertiarySystemBackground), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.32), radius: 8, y: 4)
            }
        }
        .frame(width: 280, height: 280)
        .accessibilityElement(children: .contain)
    }

    private func direction(
        _ command: RemoteCommand,
        label: LocalizedStringKey,
        symbol: String,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        RemotePressControl(
            command: command,
            accessibilityLabel: label,
            isEnabled: isEnabled,
            send: send
        ) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor.opacity(0.95))
                .frame(width: 72, height: 72)
        }
        .offset(x: x, y: y)
    }
}
