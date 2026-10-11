import SwiftUI
import AppKit

/// The unified design system for Murmur.
///
/// Refined modern aesthetic inspired by the Lemon dashboard and settings references:
/// - Dark charcoal canvas (#1E1E1E), slightly elevated sidebar (#292929),
///   floating cards (#353535), warm off-white primary text (#F5F3EA),
///   and a restrained soft-yellow accent (#FFF178).
/// - Complete light palette for system appearance support.
/// - System San Francisco typography with readable hierarchy.
/// - 4/8pt spacing grid with 12-16pt rounded card corners.
public enum DS {

    // MARK: - Colors

    public enum Color {
        // Main structural surfaces (Dark graphite first)
        public static var canvas: SwiftUI.Color {
            themeColor(light: 0xF6F5F2, dark: 0x121316)
        }

        public static var sidebar: SwiftUI.Color {
            themeColor(light: 0xEEEEEC, dark: 0x101114)
        }

        public static var card: SwiftUI.Color {
            themeColor(light: 0xFFFFFF, dark: 0x181A1F)
        }

        public static var cardElevated: SwiftUI.Color {
            themeColor(light: 0xFBFBFA, dark: 0x22242B)
        }

        public static var cardSelected: SwiftUI.Color {
            themeColor(light: 0xF0EDE6, dark: 0x20232A)
        }

        // Borders & dividers
        public static var border: SwiftUI.Color {
            themeColor(light: 0xDDDCD5, dark: 0x282B32)
        }

        public static var borderSubtle: SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.08)
            })
        }

        public static var borderGlass: SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.10)
            })
        }

        public static var borderFocus: SwiftUI.Color {
            accent
        }

        // Typography colors
        public static var textPrimary: SwiftUI.Color {
            themeColor(light: 0x181715, dark: 0xFFFFFF)
        }

        public static var textSecondary: SwiftUI.Color {
            themeColor(light: 0x6E6B63, dark: 0x8E929E)
        }

        public static var textTertiary: SwiftUI.Color {
            themeColor(light: 0x9E9A92, dark: 0x64748B)
        }

        // Accent & Brand (Restrained Murmur yellow)
        public static var accent: SwiftUI.Color {
            themeColor(light: 0xD4AF20, dark: 0xFACC15)
        }

        public static var accentSoft: SwiftUI.Color {
            themeColor(light: 0xF7EBB4, dark: 0x363219)
        }

        public static var textOnAccent: SwiftUI.Color {
            themeColor(light: 0x161614, dark: 0x121316)
        }

        /// High-contrast monochrome actions used where color would compete with content.
        public static var actionPrimarySurface: SwiftUI.Color {
            themeColor(light: 0x181715, dark: 0xFFFFFF)
        }

        public static var textOnActionPrimary: SwiftUI.Color {
            themeColor(light: 0xFFFFFF, dark: 0x121316)
        }

        // Model row actions
        public static var modelActionSurface: SwiftUI.Color {
            themeColor(light: 0xEEEEEC, dark: 0x27292E)
        }

        public static var modelActionSurfaceHover: SwiftUI.Color {
            themeColor(light: 0xE2E0DC, dark: 0x32353B)
        }

        public static var modelActionBorder: SwiftUI.Color {
            themeColor(light: 0xDDDCD5, dark: 0x3A3D44)
        }

        public static var modelActionBorderHover: SwiftUI.Color {
            themeColor(light: 0xB5B2A8, dark: 0x4A4D55)
        }

        public static var modelActionText: SwiftUI.Color {
            themeColor(light: 0x181715, dark: 0xF5F5F5)
        }

        public static var modelMenuForeground: SwiftUI.Color {
            themeColor(light: 0x181715, dark: 0xF5F5F5)
        }

        public static var modelMenuForegroundHover: SwiftUI.Color {
            themeColor(light: 0x181715, dark: 0xFFFFFF)
        }

        public static var modelMenuSurfaceHover: SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.06)
            })
        }

        public static var modelMenuBorderHover: SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.08)
            })
        }

        // State colors (Semantic)
        public static var recordRed: SwiftUI.Color {
            swatch(0xEF4444)
        }

        /// Readable red for text that requires an action on both light and dark surfaces.
        public static var actionRequired: SwiftUI.Color {
            themeColor(light: 0xB42318, dark: 0xFF8080)
        }

        public static var successGreen: SwiftUI.Color {
            swatch(0x22C55E)
        }

        public static var warningAmber: SwiftUI.Color {
            swatch(0xFF9F0A)
        }

        public static var infoBlue: SwiftUI.Color {
            swatch(0x0A84FF)
        }

        // Floating dictation HUD: brand yellow for both listening and processing.
        // A deeper gold preserves contrast against the silver face in light appearance.
        public static var hudActivity: SwiftUI.Color {
            themeColor(light: 0x806600, dark: 0xFACC15)
        }

        public static var hudSurface: SwiftUI.Color {
            themeColor(light: 0xF0EFEB, dark: 0x090A0C)
        }

        public static var hudContent: SwiftUI.Color {
            themeColor(light: 0x181715, dark: 0xF7F7F5)
        }

        public static var hudBorder: SwiftUI.Color {
            themeColor(light: 0xC9C7C0, dark: 0x2C2F35)
        }

        // Dashboard instrumentation. Each role keeps enough contrast in both appearances
        // while reserving red exclusively for an active recording.
        public static var metricWords: SwiftUI.Color {
            themeColor(light: 0x0066CC, dark: 0x64B5FF)
        }

        public static var metricAudio: SwiftUI.Color {
            themeColor(light: 0x18743A, dark: 0x4ADE80)
        }

        public static var metricLatency: SwiftUI.Color {
            themeColor(light: 0xA34A00, dark: 0xFFB454)
        }

        public static var metricTimeSaved: SwiftUI.Color {
            themeColor(light: 0x806600, dark: 0xFACC15)
        }

        // Backward compatibility mappings for legacy UI components
        public static var chassis: SwiftUI.Color { canvas }
        public static var panel: SwiftUI.Color { card }
        public static var panelHighlight: SwiftUI.Color { border }
        public static var panelShade: SwiftUI.Color { borderSubtle }
        public static var well: SwiftUI.Color { cardElevated }
        public static var deck: SwiftUI.Color { card }
        public static var cap: SwiftUI.Color { cardElevated }
        public static var seam: SwiftUI.Color { border }
        public static var ink: SwiftUI.Color { textPrimary }
        public static var inkSecondary: SwiftUI.Color { textSecondary }
        public static var silkscreen: SwiftUI.Color { textSecondary }
        public static var inkOnDeck: SwiftUI.Color { textPrimary }
        public static var record: SwiftUI.Color { recordRed }
        public static var recordIdle: SwiftUI.Color { textTertiary }
        public static var selection: SwiftUI.Color { cardSelected }
        public static var selectionEdge: SwiftUI.Color { border }
        public static var focusRing: SwiftUI.Color { accent }
        public static var hover: SwiftUI.Color { themeColor(light: 0xEEEBE2, dark: 0x2A2B2E) }
        public static var meterFace: SwiftUI.Color { cardElevated }
        public static var meterLamp: SwiftUI.Color { accent }
        public static var meterNeedle: SwiftUI.Color { textPrimary }
        public static var meterGreen: SwiftUI.Color { successGreen }
        public static var meterAmber: SwiftUI.Color { warningAmber }
        public static var meterRed: SwiftUI.Color { recordRed }

        // Helpers
        private static func swatch(_ hex: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(hex: hex)
        }

        private static func themeColor(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }

    // MARK: - Typography

    public enum Font {
        public static let pageTitle = SwiftUI.Font.system(size: 28, weight: .semibold, design: .default)
        public static let sectionTitle = SwiftUI.Font.system(size: 18, weight: .semibold, design: .default)
        public static let cardTitle = SwiftUI.Font.system(size: 15, weight: .semibold, design: .default)
        public static let cardTitleLarge = SwiftUI.Font.system(size: 16, weight: .semibold, design: .default)
        public static let statNumber = SwiftUI.Font.system(size: 18, weight: .semibold, design: .rounded)

        public static let body = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        public static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium, design: .default)
        public static let bodyLarge = SwiftUI.Font.system(size: 14, weight: .regular, design: .default)
        public static let transcriptText = SwiftUI.Font.system(size: 14, weight: .regular, design: .default)
        public static let label = SwiftUI.Font.system(size: 12, weight: .medium, design: .default)
        public static let caption = SwiftUI.Font.system(size: 11, weight: .regular, design: .default)
        public static let captionSmall = SwiftUI.Font.system(size: 10, weight: .regular, design: .default)
        public static let sidebarBrandTitle = SwiftUI.Font.system(size: 16, weight: .semibold, design: .default)
        public static let sidebarBrandSubtitle = SwiftUI.Font.system(size: 11, weight: .regular, design: .default)
        public static let sidebarLabel = SwiftUI.Font.system(size: 14, weight: .medium, design: .default)
        public static let sidebarLabelSelected = SwiftUI.Font.system(size: 14, weight: .semibold, design: .default)

        public static let counter = SwiftUI.Font.system(size: 13, design: .monospaced).monospacedDigit()
        public static let counterLarge = SwiftUI.Font.system(size: 24, weight: .semibold, design: .monospaced).monospacedDigit()

        // Backward compatibility
        public static let title = sectionTitle
        public static let silkscreen = label
        public static let silkscreenLarge = cardTitle
        public static let silkscreenTracking: CGFloat = 0.5
    }

    // MARK: - Spacing

    public enum Space {
        public static let none: CGFloat = 0
        public static let hair: CGFloat = 2
        public static let tight: CGFloat = 4
        public static let snug: CGFloat = 8
        public static let base: CGFloat = 12
        public static let roomy: CGFloat = 16
        public static let card: CGFloat = 20
        public static let wide: CGFloat = 24
        public static let panel: CGFloat = 32
        public static let generous: CGFloat = 40
    }

    // MARK: - Radius

    public enum Radius {
        public static let none: CGFloat = 0
        public static let chip: CGFloat = 6
        public static let control: CGFloat = 8
        public static let card: CGFloat = 12
        public static let cardLarge: CGFloat = 16
        public static let panel: CGFloat = 14
        public static let window: CGFloat = 16
        public static let pill: CGFloat = 999
    }

    // MARK: - Border

    public enum Border {
        public static let hairline: CGFloat = 0.5
        public static let seam: CGFloat = 1.0
        public static let standard: CGFloat = 1.0
        public static let bevel: CGFloat = 1.5
    }

    // MARK: - Layout

    public enum Layout {
        public static let sidebarWidth: CGFloat = 238
        public static let sidebarMinWidth: CGFloat = 220
        public static let sidebarMaxWidth: CGFloat = 280

        public static let settingsCompactBreakpoint: CGFloat = 700
        public static let settingsWideBreakpoint: CGFloat = 980
        public static let settingsSearchWidth: CGFloat = 280
        public static let settingsControlColumnWidth: CGFloat = 300
        public static let settingsRowMinHeight: CGFloat = 52
        public static let settingsFieldWidth: CGFloat = 220
        public static let settingsPickerWidth: CGFloat = 240
        public static let settingsDevicePickerWidth: CGFloat = 210
        public static let settingsNumericFieldWidth: CGFloat = 64
        public static let settingsMeterValueWidth: CGFloat = 40
        public static let settingsSearchHeight: CGFloat = 34

        public static let voiceModelsRowMinHeight: CGFloat = 68

        public static let personalizationSearchWidth: CGFloat = 220
        public static let personalizationEditorWidth: CGFloat = 520
        public static let personalizationExpansionMinHeight: CGFloat = 120
        public static let personalizationRowMinHeight: CGFloat = 52
        public static let personalizationTagInputMinWidth: CGFloat = 168
        public static let personalizationTagActionSize: CGFloat = 20

        public static let sidebarNavigationIconSize: CGFloat = 18
        public static let sidebarIconColumnWidth: CGFloat = 40
        public static let sidebarNavigationRowHeight: CGFloat = 36
        public static let sidebarUtilityIconSize: CGFloat = 16
        public static let sidebarUtilityIconColumnWidth: CGFloat = 20
        public static let sidebarShortcutRowHeight: CGFloat = 44
        public static let settingsSectionIconSize: CGFloat = 16
        public static let sidebarNavigationAccentWidth: CGFloat = 3
        public static let sidebarNavigationAccentHeight: CGFloat = 18
        public static let sidebarGlassTintOpacity: Double = 0.34
        public static let sidebarSurfaceOpacity: Double = 0.56
        public static let sidebarSelectedSurfaceOpacity: Double = 0.78
        public static let sidebarHoverSurfaceOpacity: Double = 0.48
        public static let sidebarHeaderTopInset: CGFloat = 44
        public static let sidebarControlCornerRadius: CGFloat = 10
        public static let sidebarKeycapCornerRadius: CGFloat = 6
    }

    // MARK: - Dashboard instrumentation

    public enum Dashboard {
        public static let waveformDisplayWidth: CGFloat = 280
        public static let waveformDisplayHeight: CGFloat = 42
        public static let waveformGraphWidth: CGFloat = 248
        public static let waveformGraphHeight: CGFloat = 28
        public static let waveformBarCount = 44
        public static let waveformBarWidth: CGFloat = 2
        public static let waveformBarSpacing: CGFloat = 3
        public static let waveformBaselineHeight: CGFloat = 1
        public static let waveformBaselineOpacity: Double = 0.10
        public static let waveformMutedOpacity: Double = 0.24
        public static let waveformSecondaryOpacity: Double = 0.58
        public static let waveformStrongOpacity: Double = 0.92
        public static let waveformAccentRadius: Double = 0.24
        public static let waveformFramesPerSecond: Double = 30
        public static let waveformEnvelopeDivisor: Double = 2.05
        public static let waveformEnvelopePower: Double = 1.45
        public static let waveformActiveSpeed: Double = 8
        public static let waveformActivePhaseStep: Double = 0.73
        public static let waveformActiveMinimumAmplitude: CGFloat = 0.30
        public static let waveformActiveGain: CGFloat = 2.20
        public static let waveformActiveEdgeFloor: CGFloat = 0.55
        public static let waveformActiveEdgeGain: CGFloat = 0.45
        public static let waveformActiveBaseHeight: CGFloat = 10
        public static let waveformActiveSignalHeight: CGFloat = 20
        public static let waveformProcessingSpeed: Double = 5
        public static let waveformProcessingPhaseStep: Double = 0.42
        public static let waveformProcessingBaseHeight: CGFloat = 4
        public static let waveformProcessingSignalHeight: CGFloat = 14
        public static let waveformIdlePhaseStep: Double = 0.78
        public static let waveformIdleBaseHeight: CGFloat = 2
        public static let waveformIdleEnvelopeHeight: CGFloat = 2
        public static let waveformIdleSignalHeight: CGFloat = 7

        public static let statisticIconSize: CGFloat = 21
        public static let statisticIconFrame: CGFloat = 36
        public static let statisticIconSurfaceOpacity: Double = 0.12
        public static let statisticIconBorderOpacity: Double = 0.24

        public static let transcriptCardSpacing: CGFloat = 10
        public static let transcriptCardPadding: CGFloat = 16
        public static let transcriptActionSize: CGFloat = 32
        public static let transcriptActionIconSize: CGFloat = 15
        public static let transcriptActionRestScale: CGFloat = 1
        public static let transcriptActionHoverScale: CGFloat = 1.08
        public static let transcriptCopyConfirmationDuration: TimeInterval = 1.2
    }

    // MARK: - Floating dictation HUD

    public enum HUD {
        public static let compactWidth: CGFloat = 94
        public static let messageWidth: CGFloat = 184
        public static let errorWidth: CGFloat = 204
        public static let height: CGFloat = 40
        public static let outerPadding: CGFloat = 10
        public static let horizontalPadding: CGFloat = 14

        public static let waveformBarCount = 12
        public static let waveformBarWidth: CGFloat = 3
        public static let waveformBarSpacing: CGFloat = 3
        public static let waveformHeight: CGFloat = 22
        public static let waveformMinimumBarHeight: CGFloat = 4
        public static let waveformBarTravel: CGFloat = 16
        public static let waveformAnimationDuration: TimeInterval = 0.08

        public static let processingFrameInterval: TimeInterval = 1.0 / 24.0
        public static let processingSpeed: Double = 5.2
        public static let processingPhaseStep: Double = 0.78
        public static let processingMinimumLevel: Double = 0.16
        public static let processingLevelRange: Double = 0.56
        public static let processingEnvelopeFloor: Double = 0.55
        public static let processingEnvelopeGain: Double = 0.45
        public static let processingRestingLevel: Double = 0.36

        public static let statusSpacing: CGFloat = 8
        public static let statusIconSize: CGFloat = 16
        public static let dismissButtonWidth: CGFloat = 24
        public static let dismissButtonHeight: CGFloat = 28
        public static let panelTransitionDuration: TimeInterval = 0.18
        public static let resizeDelayMilliseconds = 180
    }

    // MARK: - Voice model catalog

    public enum VoiceModels {
        public static let activeIconFrame: CGFloat = 40
        public static let activeDotSize: CGFloat = 5
        public static let activePulseScale: CGFloat = 2.4
        public static let activePulseRestOpacity: Double = 0.42
        public static let activePulseLiveOpacity: Double = 0
        public static let activeStatusSurfaceOpacity: Double = 0.16
        public static let activeStatusBorderOpacity: Double = 0.46
        public static let activeStatusDotOpacity: Double = 0.86
        public static let profileSeparatorHeight: CGFloat = 14
        public static let overflowDotCount: Int = 3
        public static let overflowDotSize: CGFloat = 3
        public static let actionHoverOpacity: Double = 0.88
        public static let actionHoverScale: CGFloat = 1.02

        // Model row action area specifications
        public static let actionAreaWidth: CGFloat = 150
        public static let actionHeight: CGFloat = 34
        public static let actionButtonMinWidth: CGFloat = 92
        public static let actionHorizontalPadding: CGFloat = 13
        public static let actionCornerRadius: CGFloat = 7
        public static let actionGap: CGFloat = 8
        public static let actionTrailingPadding: CGFloat = 2
        public static let menuButtonSize: CGFloat = 34
        public static let moreIconSize: CGFloat = 18
    }

    // MARK: - Application icon

    public enum AppIcon {
        public static let background = SwiftUI.Color(hex: 0x101114)
        public static let border = SwiftUI.Color(hex: 0x2A2D35)
        public static let mark = SwiftUI.Color(hex: 0xFACC15)

        public static let sidebarSize: CGFloat = 40
        public static let aboutSize: CGFloat = 64
        public static let cornerRadiusRatio: CGFloat = 0.28
        public static let barWidthRatio: CGFloat = 0.072
        public static let barGapRatio: CGFloat = 0.050
        public static let maxBarHeightRatio: CGFloat = 0.46
    }

    // MARK: - Elevation & Shadow

    public enum Shadow {
        public static let subtle = Spec(color: SwiftUI.Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
        public static let card = Spec(color: SwiftUI.Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
        public static let elevated = Spec(color: SwiftUI.Color.black.opacity(0.25), radius: 16, x: 0, y: 6)
        public static let dropdown = Spec(color: SwiftUI.Color.black.opacity(0.30), radius: 20, x: 0, y: 8)

        // Compatibility
        public static let raised = subtle
        public static let pressed = Spec(color: SwiftUI.Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        public static let panel = card
        public static let window = elevated

        public struct Spec: Sendable {
            public let color: SwiftUI.Color
            public let radius: CGFloat
            public let x: CGFloat
            public let y: CGFloat
        }
    }

    // MARK: - Motion

    public enum Motion {
        public static let hover = Animation.easeOut(duration: 0.12)
        public static let press = Animation.easeOut(duration: 0.08)
        public static let release = Animation.easeOut(duration: 0.14)
        public static let transition = Animation.easeInOut(duration: 0.20)
        public static let panel = Animation.easeInOut(duration: 0.18)
        public static let lamp = Animation.easeOut(duration: 0.08)
        public static let activePulse = Animation.easeOut(duration: 1.6).repeatForever(autoreverses: false)

        public static let needleAttack: TimeInterval = 0.20
        public static let needleRelease: TimeInterval = 0.35
        public static let needleOvershoot: Double = 0.04
    }

    // MARK: - Materials & UI details

    public enum Material {
        public static let lampSize: CGFloat = 8
        public static let lampSpecular: Double = 0.4
        public static let lampUnlitOpacity: Double = 0.3
        public static let keyHeight: CGFloat = 34
        public static let keyMinWidth: CGFloat = 52
        public static let keyTravel: CGFloat = 1.0

        // Common layout dimensions
        public static let iconSizeSmall: CGFloat = 12
        public static let iconSizeBase: CGFloat = 16
        public static let iconSizeLarge: CGFloat = 24
        public static let iconSizeHero: CGFloat = 36
        public static let dropZoneHeight: CGFloat = 160
        public static let minTextEditorHeight: CGFloat = 180

        // Compatibility dummy properties
        public static let grainLight: Double = 0
        public static let grainDark: Double = 0
        public static let grainPitch: CGFloat = 0
        public static let grainAngle: Angle = .degrees(0)
        public static let screwSize: CGFloat = 0
        public static let screwInset: CGFloat = 0
        public static let ventSlotWidth: CGFloat = 0
        public static let ventSlotHeight: CGFloat = 0
        public static let ventSlotGap: CGFloat = 0
        public static let ventRadius: CGFloat = 0
        public static let segmentThickness: CGFloat = 2
        public static let segmentGap: CGFloat = 1
        public static let segmentGhostOpacity: Double = 0.1
        public static let buttonRestScale: CGFloat = 1
        public static let buttonPressedScale: CGFloat = 0.98
        public static let helperDashLength: CGFloat = 5
        public static let helperDashGap: CGFloat = 4
        public static let needleSweep: Angle = .degrees(90)
        public static let needleWidth: CGFloat = 1.5
        public static let meterZeroPoint: Double = 0.75
    }
}

// MARK: - Color Hex Extensions

public extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

public extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
