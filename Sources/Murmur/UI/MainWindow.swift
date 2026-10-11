import SwiftUI
import MurmurDictionary
import AppKit

/// Primary navigation destinations in Murmur.
public enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case meetings = "Meetings"
    case models = "Models"
    case fileTranscription = "File Transcription"
    case personalization = "Personalization"
    case settings = "Settings"

    public var id: String { rawValue }

    public var lucide: LucideIcon.Name {
        switch self {
        case .dashboard: return .home
        case .meetings: return .mic
        case .models: return .cpu
        case .fileTranscription: return .fileText
        case .personalization: return .sparkles
        case .settings: return .settings
        }
    }
}

/// The unified main application window shell for Murmur.
struct MainWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var selectedDestination: SidebarDestination? = .dashboard
    @State private var isShowingAbout = false
    @State private var isShowingShortcutPicker = false

    init(controller: DictationController) {
        self.controller = controller
    }

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(
                    min: DS.Layout.sidebarMinWidth,
                    ideal: DS.Layout.sidebarWidth,
                    max: DS.Layout.sidebarMaxWidth
                )
        } detail: {
            Group {
                switch selectedDestination ?? .dashboard {
                case .dashboard:
                    DashboardView(controller: controller)
                case .meetings:
                    MeetingsView()
                case .models:
                    ModelsWorkspaceView()
                case .fileTranscription:
                    FileTranscriptionView()
                case .personalization:
                    PersonalizationView()
                case .settings:
                    SettingsView(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if MeetingController.shared.isBusy { MeetingStatusView() }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
        .tint(DS.Color.accent)
        .sheet(isPresented: $isShowingAbout) {
            AboutDialog()
        }
        .sheet(isPresented: $isShowingShortcutPicker) {
            ShortcutRecorderSheet(controller: controller)
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNavigate)) { notif in
            if let dest = notif.object as? SidebarDestination {
                selectedDestination = dest
            } else if let destStr = notif.object as? String {
                if destStr.caseInsensitiveCompare("history") == .orderedSame {
                    selectedDestination = .dashboard
                } else if destStr.caseInsensitiveCompare("dictionary") == .orderedSame {
                    selectedDestination = .personalization
                } else if destStr.caseInsensitiveCompare("models") == .orderedSame || destStr == "writing-models" {
                    selectedDestination = .models
                } else if let dest = SidebarDestination.allCases.first(where: {
                    $0.rawValue.caseInsensitiveCompare(destStr) == .orderedSame ||
                    $0.id.caseInsensitiveCompare(destStr) == .orderedSame
                }) {
                    selectedDestination = dest
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Branding Header (clears macOS traffic lights)
            HStack(spacing: DS.Space.snug) {
                MurmurAppIcon(size: DS.AppIcon.sidebarSize)
                    .frame(width: DS.Layout.sidebarIconColumnWidth)

                VStack(alignment: .leading, spacing: DS.Space.hair) {
                    Text(Branding.appName)
                        .font(DS.Font.sidebarBrandTitle)
                        .foregroundStyle(DS.Color.textPrimary)

                    Text("100% Local Transcription")
                        .font(DS.Font.sidebarBrandSubtitle)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, DS.Space.roomy)
            .padding(.top, DS.Layout.sidebarHeaderTopInset)
            .padding(.bottom, DS.Space.card)

            List {
                ForEach(SidebarDestination.allCases) { destination in
                    SidebarNavigationRow(
                        destination: destination,
                        isSelected: selectedDestination == destination
                    ) {
                        selectedDestination = destination
                    }
                    .listRowInsets(
                        EdgeInsets(
                            top: DS.Space.hair,
                            leading: DS.Space.roomy,
                            bottom: DS.Space.hair,
                            trailing: DS.Space.roomy
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)

            // The whole compact row opens the shortcut editor, avoiding nested controls
            // and preserving a single-line label at the sidebar's minimum width.
            Button {
                isShowingShortcutPicker = true
            } label: {
                HStack(spacing: DS.Space.tight) {
                    LucideIcon(.keyboard, size: DS.Layout.sidebarUtilityIconSize)
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(width: DS.Layout.sidebarUtilityIconColumnWidth)

                    Text("Push to Talk")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)

                    Spacer(minLength: DS.Space.tight)

                    Text(settings.shortcut.displayName)
                        .font(DS.Font.counter)
                        .foregroundStyle(DS.Color.textPrimary)
                        .padding(.horizontal, DS.Space.tight)
                        .padding(.vertical, DS.Space.tight)
                        .background(DS.Color.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                        )
                        .fixedSize()
                }
                .padding(.horizontal, DS.Space.snug)
                .frame(minHeight: DS.Layout.sidebarShortcutRowHeight)
                .contentShape(Rectangle())
                .background(DS.Color.card.opacity(DS.Layout.sidebarSurfaceOpacity))
                .clipShape(RoundedRectangle(cornerRadius: DS.Layout.sidebarControlCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Layout.sidebarControlCornerRadius)
                        .strokeBorder(DS.Color.borderGlass, lineWidth: DS.Border.standard)
                )
            }
            .buttonStyle(.plain)
            .help("Change dictation shortcut (\(settings.shortcut.displayName))")
            .accessibilityLabel("Change dictation shortcut, currently \(settings.shortcut.displayName)")
            .padding(.horizontal, DS.Space.roomy)
            .padding(.bottom, DS.Space.snug)

            Divider()
                .overlay(DS.Color.borderSubtle)
                .padding(.horizontal, DS.Space.base)
                .padding(.bottom, DS.Space.snug)

            // About Murmur button
            Button {
                isShowingAbout = true
            } label: {
                HStack(spacing: DS.Space.snug) {
                    LucideIcon(.info, size: DS.Layout.sidebarNavigationIconSize)
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(width: DS.Layout.sidebarIconColumnWidth)
                    Text("About Murmur")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.Space.roomy)
            .padding(.bottom, DS.Space.snug)

            // Sidebar Footer
            HStack {
                Text(Branding.byline)
                Spacer()
                Text("v\(Branding.versionString)")
            }
            .font(DS.Font.captionSmall)
            .foregroundStyle(DS.Color.textTertiary)
            .padding(.horizontal, DS.Space.roomy)
            .padding(.bottom, DS.Space.roomy)
        }
    }
}

private struct SidebarNavigationRow: View {
    let destination: SidebarDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.snug) {
                LucideIcon(destination.lucide, size: DS.Layout.sidebarNavigationIconSize)
                    .frame(width: DS.Layout.sidebarIconColumnWidth)

                Text(destination.rawValue)
                    .font(isSelected ? DS.Font.sidebarLabelSelected : DS.Font.sidebarLabel)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? DS.Color.textPrimary : DS.Color.textSecondary)
            .frame(minHeight: DS.Layout.sidebarNavigationRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? DS.Color.cardSelected.opacity(DS.Layout.sidebarSelectedSurfaceOpacity)
                    : (isHovered
                        ? DS.Color.hover.opacity(DS.Layout.sidebarHoverSurfaceOpacity)
                        : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(
                        isFocused ? DS.Color.borderFocus : (isSelected ? DS.Color.borderGlass : Color.clear),
                        lineWidth: isFocused ? DS.Border.bevel : DS.Border.hairline
                    )
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .accessibilityLabel(destination.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - About Dialog

private struct AboutDialog: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DS.Space.roomy) {
            MurmurAppIcon(size: DS.AppIcon.aboutSize)
            .padding(.top, DS.Space.base)

            VStack(spacing: 4) {
                Text(Branding.appName)
                    .font(DS.Font.pageTitle)
                    .foregroundStyle(DS.Color.textPrimary)

                Text(Branding.byline)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.accent)

                Text("Version \(Branding.versionString)")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Text("Push-to-talk on-device speech dictation for macOS.\nNeural Engine transcription via Apple Speech and NVIDIA Parakeet.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.base)

            Text("All transcription runs locally and privately on your Mac.")
                .font(DS.Font.captionSmall)
                .foregroundStyle(DS.Color.textTertiary)

            MurmurButton("Done", lucide: .check, style: .primary) {
                dismiss()
            }
            .frame(width: 120)
            .padding(.bottom, DS.Space.base)
        }
        .padding(DS.Space.wide)
        .frame(width: 380)
        .background(DS.Color.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(DS.Color.borderGlass, lineWidth: 1)
        )
    }
}
