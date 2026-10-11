import SwiftUI

/// A quiet, opaque face for the dictation indicator. The HUD stays visually stable
/// over every app beneath it instead of changing contrast with the desktop content.
@MainActor
struct MurmurHUDMaterial: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(DS.Color.hudSurface, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        contrast == .increased ? DS.Color.hudContent : DS.Color.hudBorder,
                        lineWidth: DS.Border.hairline
                    )
                    .allowsHitTesting(false)
            }
    }
}
