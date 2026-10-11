import SwiftUI

/// Standard Settings window opened via ⌘, or application menu.
/// Reuses the unified SettingsView experience.
struct SettingsWindow: View {
    @Bindable var controller: DictationController

    var body: some View {
        SettingsView(controller: controller)
            .frame(minWidth: 760, minHeight: 540)
            .tint(DS.Color.accent)
    }
}
