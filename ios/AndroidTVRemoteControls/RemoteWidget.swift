import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct RemoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetRemoteBridge.widgetKind, provider: RemoteTimelineProvider()) {
            entry in
            RemoteWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("TV Remote")
        .description("Control a connected TV without opening the app")
        .supportedFamilies([.systemSmall, .systemMedium])
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
        RemoteWidgetContent(snapshot: entry.snapshot, family: family)
    }
}
