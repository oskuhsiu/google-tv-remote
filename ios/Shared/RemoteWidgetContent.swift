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
        case .systemLarge:
            largeLayout
        default:
            RemoteWidgetPad(snapshot: snapshot)
                .padding(8)
        }
    }

    private var mediumLayout: some View {
        GeometryReader { proxy in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "av.remote.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .widgetAccentable()

                    tvName

                    WidgetStatusLabel(availability: snapshot.availability, showsText: true)

                    Spacer(minLength: 0)
                }
                .frame(width: proxy.size.width * 0.34, alignment: .leading)

                Divider()

                RemoteWidgetPad(snapshot: snapshot)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                tvName
                WidgetStatusLabel(availability: snapshot.availability, showsText: true)
            }
            .fixedSize(horizontal: false, vertical: true)

            RemoteWidgetPad(snapshot: snapshot)
        }
        .padding(12)
    }

    private var tvName: some View {
        Text(snapshot.tvName ?? String(localized: "TV Remote"))
            .font(.headline)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 18.0, *)
private struct RemoteWidgetPad: View {
    @ScaledMetric(relativeTo: .body) private var glyphScale: CGFloat = 1

    let snapshot: WidgetRemoteSnapshot

    var body: some View {
        GeometryReader { proxy in
            let side = max(0, min(proxy.size.width, proxy.size.height))
            let spacing = min(10, max(4, side * 0.025))
            let cell = max(0, (side - spacing * 2) / 3)

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
            .font(.system(size: glyphSize(for: size), weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(isPrimary ? Color.accentColor : Color.primary.opacity(0.07))
                    .widgetAccentable(isPrimary)
            }
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
                .font(.system(size: glyphSize(for: size), weight: .semibold))
                .foregroundStyle(.tint)
                .widgetAccentable()
                .frame(width: size, height: size)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open remote")
    }

    private func glyphSize(for cell: CGFloat) -> CGFloat {
        min(cell * 0.5, max(13, cell * 0.34) * glyphScale)
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
