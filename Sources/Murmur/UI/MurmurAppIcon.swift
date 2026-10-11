import SwiftUI

/// Murmur's canonical black app mark, shared by branded application surfaces.
///
/// The raster app icon is generated from the same colors and waveform proportions in
/// `Tools/makeicon.swift`, keeping Finder, Spotlight, Dock, sidebar, and About consistent.
struct MurmurAppIcon: View {
    let size: CGFloat

    private let barHeights: [CGFloat] = [0.30, 0.52, 0.78, 1.00, 0.82, 0.56, 0.34]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * DS.AppIcon.cornerRadiusRatio, style: .continuous)
                .fill(DS.AppIcon.background)
                .overlay {
                    RoundedRectangle(cornerRadius: size * DS.AppIcon.cornerRadiusRatio, style: .continuous)
                        .strokeBorder(DS.AppIcon.border, lineWidth: DS.Border.standard)
                }

            HStack(spacing: size * DS.AppIcon.barGapRatio) {
                ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                    Capsule()
                        .fill(DS.AppIcon.mark)
                        .frame(
                            width: size * DS.AppIcon.barWidthRatio,
                            height: max(
                                size * DS.AppIcon.barWidthRatio,
                                size * DS.AppIcon.maxBarHeightRatio * height
                            )
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
