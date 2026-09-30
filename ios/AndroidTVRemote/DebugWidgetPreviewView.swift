#if DEBUG
import SwiftUI
import WidgetKit

struct DebugWidgetPreviewView: View {
    private let readySnapshot = WidgetRemoteSnapshot(
        tvName: "Living Room TV",
        availability: .ready
    )
    private let unavailableSnapshot = WidgetRemoteSnapshot(
        tvName: "Living Room TV",
        availability: .unavailable
    )
    private let longNameSnapshot = WidgetRemoteSnapshot(
        tvName: "Living Room and Entertainment Center Television 客廳電視",
        availability: .ready
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                HStack(spacing: 16) {
                    previewSurface(
                        width: 158,
                        height: 158,
                        family: .systemSmall,
                        snapshot: readySnapshot
                    )
                    previewSurface(
                        width: 158,
                        height: 158,
                        family: .systemSmall,
                        snapshot: unavailableSnapshot
                    )
                }
                previewSurface(
                    width: 338,
                    height: 158,
                    family: .systemMedium,
                    snapshot: readySnapshot
                )
                previewSurface(
                    width: 338,
                    height: 158,
                    family: .systemMedium,
                    snapshot: unavailableSnapshot
                )
                largePreview(title: "Large · Ready", snapshot: readySnapshot)
                largePreview(title: "Large · Unavailable", snapshot: unavailableSnapshot)
                largePreview(title: "Large · Long TV name", snapshot: longNameSnapshot)
                largePreview(title: "Large · Accessibility text", snapshot: longNameSnapshot)
                    .environment(\.dynamicTypeSize, .accessibility3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private func largePreview(title: String, snapshot: WidgetRemoteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)
            previewSurface(width: 338, height: 354, family: .systemLarge, snapshot: snapshot)
        }
    }

    private func previewSurface(
        width: CGFloat,
        height: CGFloat,
        family: WidgetFamily,
        snapshot: WidgetRemoteSnapshot
    ) -> some View {
        RemoteWidgetContent(snapshot: snapshot, family: family)
            .frame(width: width, height: height)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
    }
}
#endif
