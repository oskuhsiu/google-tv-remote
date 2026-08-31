import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct RemoteWidgetContent: View {
    let snapshot: WidgetRemoteSnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemMedium:
            mediumLayout
        default:
            RemoteWidgetPad(snapshot: snapshot)
                .padding(8)
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "av.remote.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)

                Text(snapshot.tvName ?? String(localized: "TV Remote"))
                    .font(.headline)
                    .lineLimit(2)

                WidgetStatusLabel(availability: snapshot.availability, showsText: true)

                Spacer(minLength: 0)
            }
            .frame(width: 112, alignment: .leading)

            Divider()

            RemoteWidgetPad(snapshot: snapshot)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

@available(iOS 18.0, *)
private struct RemoteWidgetPad: View {
    let snapshot: WidgetRemoteSnapshot

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let side = min(proxy.size.width, proxy.size.height)
            let cell = (side - spacing * 2) / 3

            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                GridRow {
                    WidgetStatusLabel(availability: snapshot.availability, showsText: false)
                        .frame(width: cell, height: cell)
                    commandButton(.up, symbol: "chevron.up", label: "Up", size: cell)
                    openRemoteButton(size: cell)
                }
                GridRow {
                    commandButton(.left, symbol: "chevron.left", label: "Left", size: cell)
                    commandButton(.select, symbol: nil, label: "OK", size: cell, isPrimary: true)
                    commandButton(.right, symbol: "chevron.right", label: "Right", size: cell)
                }
                GridRow {
                    commandButton(
                        .back,
                        symbol: "arrow.uturn.backward",
                        label: "Back",
                        size: cell
                    )
                    commandButton(.down, symbol: "chevron.down", label: "Down", size: cell)
                    commandButton(.home, symbol: "house.fill", label: "Home", size: cell)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func commandButton(
        _ command: WidgetRemoteCommand,
        symbol: String?,
        label: LocalizedStringResource,
        size: CGFloat,
        isPrimary: Bool = false
    ) -> some View {
        Button(intent: SendWidgetRemoteCommandIntent(command: command)) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                } else {
                    Text(label)
                }
            }
            .font(.system(size: max(13, size * 0.34), weight: .semibold))
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background(
                isPrimary ? Color.accentColor : Color.primary.opacity(0.07),
                in: Circle()
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!snapshot.isReady)
        .opacity(snapshot.isReady ? 1 : 0.38)
        .accessibilityLabel(Text(label))
        .accessibilityHint(
            snapshot.isReady
                ? Text("Send to TV")
                : Text("Open the app to connect")
        )
    }

    private func openRemoteButton(size: CGFloat) -> some View {
        Button(intent: OpenCompactRemoteIntent()) {
            Image(systemName: "arrow.up.forward.app.fill")
                .font(.system(size: max(13, size * 0.32), weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: size, height: size)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open remote")
    }
}

private struct WidgetStatusLabel: View {
    let availability: WidgetRemoteAvailability
    let showsText: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            if showsText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
    }

    private var statusText: LocalizedStringKey {
        switch availability {
        case .ready:
            "Connected"
        case .connecting:
            "Connecting…"
        case .unavailable:
            "Open app"
        }
    }

    private var color: Color {
        switch availability {
        case .ready:
            .green
        case .connecting:
            .orange
        case .unavailable:
            .secondary
        }
    }
}
