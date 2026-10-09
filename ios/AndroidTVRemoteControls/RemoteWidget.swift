import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct RemoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetRemoteBridge.widgetKind, provider: RemoteTimelineProvider()) {
            entry in
            RemoteWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "androidtvremote://compact"))
        }
        .configurationDisplayName("TV Remote")
        .description("Control a connected TV from the Home Screen or Lock Screen. Requires Keep Ready in the background.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular
        ])
        .contentMarginsDisabled()
    }
}

private struct RemoteTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetRemoteSnapshot
}

private struct RemoteTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemoteTimelineEntry {
        RemoteTimelineEntry(
            date: Date(),
            snapshot: WidgetRemoteSnapshot(tvName: "Living Room TV", availability: .ready)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RemoteTimelineEntry) -> Void) {
        let snapshot = context.isPreview
            ? WidgetRemoteSnapshot(tvName: "Living Room TV", availability: .ready)
            : WidgetRemoteBridge.loadSnapshot()
        completion(RemoteTimelineEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemoteTimelineEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetRemoteBridge.loadSnapshot(at: now)
        var entries = [RemoteTimelineEntry(date: now, snapshot: snapshot)]
        let policy: TimelineReloadPolicy

        if let expiration = snapshot.leaseExpiration {
            entries.append(
                RemoteTimelineEntry(
                    date: expiration,
                    snapshot: snapshot.unavailable(at: expiration)
                )
            )
            policy = .atEnd
        } else {
            policy = .never
        }

        completion(Timeline(entries: entries, policy: policy))
    }
}

@available(iOSApplicationExtension 18.0, *)
private struct RemoteWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: RemoteTimelineEntry

    var body: some View {
        switch family {
        case .accessoryRectangular, .accessoryCircular:
            LockScreenRemoteContent(snapshot: entry.snapshot, family: family)
        default:
            RemoteWidgetContent(snapshot: entry.snapshot, family: family)
        }
    }
}

/// Accessory widgets use the system's vibrant rendering, not Home Screen colors.
/// iOS may require authentication for these buttons; the TV Command control is
/// the separate Lock Screen surface whose intent allows locked execution.
@available(iOSApplicationExtension 18.0, *)
private struct LockScreenRemoteContent: View {
    let snapshot: WidgetRemoteSnapshot
    let family: WidgetFamily

    private let compactURL = URL(string: "androidtvremote://compact")!

    var body: some View {
        if snapshot.isReady {
            if family == .accessoryCircular {
                commandButton(.select)
                    .background { AccessoryWidgetBackground() }
            } else {
                // Two rows preserve larger touch targets than a three-row D-pad.
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        commandButton(.left)
                        commandButton(.up)
                        commandButton(.right)
                    }
                    HStack(spacing: 3) {
                        commandButton(.back)
                        commandButton(.down)
                        commandButton(.select)
                    }
                }
                .padding(2)
            }
        } else {
            Link(destination: compactURL) {
                if family == .accessoryCircular {
                    Image(systemName: "av.remote.fill")
                        .font(.title2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background { AccessoryWidgetBackground() }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Open TV Remote", systemImage: "av.remote.fill")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Connect and enable Keep Ready")
                            .font(.caption2)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .accessibilityLabel("Open TV Remote to connect and enable Keep Ready")
        }
    }

    private func commandButton(_ command: WidgetRemoteCommand) -> some View {
        Button(intent: SendWidgetRemoteCommandIntent(command: command)) {
            Group {
                if command == .select {
                    Text("OK")
                } else {
                    Image(systemName: command.symbolName)
                }
            }
            .font(.system(size: family == .accessoryCircular ? 19 : 15, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if family != .accessoryCircular {
                    RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(command.controlTitle))
        .accessibilityHint("Send to TV")
    }
}

#Preview("Lock Screen - connected", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteTimelineEntry(date: .now, snapshot: WidgetRemoteSnapshot(tvName: "TV", availability: .ready))
}

#Preview("Lock Screen - reconnect", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteTimelineEntry(date: .now, snapshot: .unavailable)
}

#Preview("Lock Screen - OK", as: .accessoryCircular) {
    RemoteWidget()
} timeline: {
    RemoteTimelineEntry(date: .now, snapshot: WidgetRemoteSnapshot(tvName: "TV", availability: .ready))
}
