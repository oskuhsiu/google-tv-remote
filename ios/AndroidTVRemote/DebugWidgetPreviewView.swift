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
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
