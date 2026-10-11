import SwiftUI
import AppKit

/// Unified Lucide icon system for Murmur.
///
/// Provides pixel-perfect Lucide vector icons rendered natively with SwiftUI and AppKit.
/// Icons default to ~16-18px for standard UI controls and ~18-20px for the sidebar,
/// with consistent ~1.75-2px stroke geometry.
public struct LucideIcon: View {
    public enum Name: String, CaseIterable, Sendable {
        case layoutDashboard
        case home
        case history
        case zap
        case cpu
        case fileAudio
        case bookOpen
        case settings
        case mic
        case micOff
        case copy
        case check
        case clock
        case fileText
        case keyboard
        case chevronDown
        case chevronRight
        case chevronLeft
        case moreHorizontal
        case ellipsis
        case download
        case trash2
        case search
        case play
        case pause
        case stop
        case info
        case alertCircle
        case circleAlert
        case sparkles
        case sparkleFilled
        case brushCleaning, fileSearch, pencil, smile, briefcase, alignLeft, list, listChecks, table
        case arrowRight
        case sliders
        case folder
        case plus
        case xmark
        case x
        case square
        case loaderCircle
        case waveform
        case activity
        case target
        case uploadCloud
        case globe
        case shield
        case palette
        case wrench
        case userRound
        case slidersHorizontal
    }

    public let name: Name
    public var size: CGFloat
    public var strokeWidth: CGFloat

    public init(_ name: Name, size: CGFloat = 16, strokeWidth: CGFloat = 1.75) {
        self.name = name
        self.size = size
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        if let nsImage = LucideCache.shared.image(for: name, strokeWidth: strokeWidth) {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Rectangle()
                .fill(Color.clear)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - In-Memory SVG Cache & Path Definitions

@MainActor
final class LucideCache {
    static let shared = LucideCache()
    private var cache: [String: NSImage] = [:]

    func image(for name: LucideIcon.Name, strokeWidth: CGFloat) -> NSImage? {
        let key = "\(name.rawValue)_\(strokeWidth)"
        if let existing = cache[key] {
            return existing
        }
        guard let svgString = svgTemplate(for: name, strokeWidth: strokeWidth) else {
            return nil
        }
        guard let data = svgString.data(using: .utf8),
              let image = NSImage(data: data) else {
            return nil
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }

    private func svgTemplate(for name: LucideIcon.Name, strokeWidth: CGFloat) -> String? {
        let inner = pathContent(for: name)
        let strokeStr = String(format: "%.2f", strokeWidth)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="\(strokeStr)" stroke-linecap="round" stroke-linejoin="round">
        \(inner)
        </svg>
        """
    }

    private func pathContent(for name: LucideIcon.Name) -> String {
        switch name {
        case .layoutDashboard:
            return """
            <rect width="7" height="9" x="3" y="3" rx="1"/>
            <rect width="7" height="5" x="14" y="3" rx="1"/>
            <rect width="7" height="9" x="14" y="12" rx="1"/>
            <rect width="7" height="5" x="3" y="16" rx="1"/>
            """
        case .home:
            return """
            <path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>
            <polyline points="9 22 9 12 15 12 15 22"/>
            """
        case .history:
            return """
            <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
            <path d="M3 3v5h5"/>
            <path d="M12 7v5l4 2"/>
            """
        case .zap:
            return """
            <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
            """
        case .cpu:
            return """
            <rect width="16" height="16" x="4" y="4" rx="2"/>
            <rect width="6" height="6" x="9" y="9" rx="1"/>
            <path d="M15 2v2"/><path d="M15 20v2"/><path d="M2 15h2"/>
            <path d="M2 9h2"/><path d="M20 15h2"/><path d="M20 9h2"/>
            <path d="M9 2v2"/><path d="M9 20v2"/>
            """
        case .fileAudio:
            return """
            <path d="M17.5 22h.5a2 2 0 0 0 2-2V7l-5-5H6a2 2 0 0 0-2 2v3"/>
            <path d="M14 2v4a2 2 0 0 0 2 2h4"/>
            <path d="M2 19a2 2 0 1 1 4 0v1a2 2 0 1 1-4 0v-4a6 6 0 0 1 12 0v4a2 2 0 1 1-4 0v-1a2 2 0 1 1 4 0"/>
            """
        case .bookOpen:
            return """
            <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/>
            <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>
            """
        case .settings:
            return """
            <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/>
            <circle cx="12" cy="12" r="3"/>
            """
        case .mic:
            return """
            <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/>
            <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
            <line x1="12" x2="12" y1="19" y2="22"/>
            """
        case .micOff:
            return """
            <line x1="2" x2="22" y1="2" y2="22"/>
            <path d="M18.89 13.23A7.12 7.12 0 0 0 19 12v-2"/>
            <path d="M5 10v2a7 7 0 0 0 12 5"/>
            <path d="M15 9.34V5a3 3 0 0 0-5.68-1.33"/>
            <path d="M9 9v3a3 3 0 0 0 5.12 2.12"/>
            <line x1="12" x2="12" y1="19" y2="22"/>
            """
        case .copy:
            return """
            <rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>
            <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>
            """
        case .check:
            return """
            <path d="M20 6 9 17l-5-5"/>
            """
        case .clock:
            return """
            <circle cx="12" cy="12" r="10"/>
            <polyline points="12 6 12 12 16 14"/>
            """
        case .fileText:
            return """
            <path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/>
            <path d="M14 2v4a2 2 0 0 0 2 2h4"/>
            <path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>
            """
        case .keyboard:
            return """
            <path d="M10 8h.01"/><path d="M12 12h.01"/><path d="M14 8h.01"/>
            <path d="M16 12h.01"/><path d="M18 8h.01"/><path d="M6 8h.01"/>
            <path d="M7 16h10"/><path d="M8 12h.01"/>
            <rect width="20" height="16" x="2" y="4" rx="2"/>
            """
        case .chevronDown:
            return """
            <path d="m6 9 6 6 6-6"/>
            """
        case .chevronRight:
            return """
            <path d="m9 18 6-6-6-6"/>
            """
        case .chevronLeft:
            return """
            <path d="m15 18-6-6 6-6"/>
            """
        case .moreHorizontal, .ellipsis:
            return """
            <circle cx="12" cy="12" r="1.5" fill="black"/>
            <circle cx="19" cy="12" r="1.5" fill="black"/>
            <circle cx="5" cy="12" r="1.5" fill="black"/>
            """
        case .download:
            return """
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
            <polyline points="7 10 12 15 17 10"/>
            <line x1="12" x2="12" y1="15" y2="3"/>
            """
        case .trash2:
            return """
            <path d="M3 6h18"/>
            <path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/>
            <path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/>
            <line x1="10" x2="10" y1="11" y2="17"/>
            <line x1="14" x2="14" y1="11" y2="17"/>
            """
        case .search:
            return """
            <circle cx="11" cy="11" r="8"/>
            <path d="m21 21-4.3-4.3"/>
            """
        case .play:
            return """
            <polygon points="6 3 20 12 6 21 6 3"/>
            """
        case .pause:
            return """
            <rect width="4" height="16" x="6" y="4"/>
            <rect width="4" height="16" x="14" y="4"/>
            """
        case .stop:
            return """
            <rect width="16" height="16" x="4" y="4" rx="2"/>
            """
        case .info:
            return """
            <circle cx="12" cy="12" r="10"/>
            <path d="M12 16v-4"/>
            <path d="M12 8h.01"/>
            """
        case .alertCircle, .circleAlert:
            return """
            <circle cx="12" cy="12" r="10"/>
            <line x1="12" x2="12" y1="8" y2="12"/>
            <line x1="12" x2="12.01" y1="16" y2="16"/>
            """
        case .square:
            return """
            <rect width="14" height="14" x="5" y="5" rx="2" fill="black"/>
            """
        case .loaderCircle:
            return """
            <path d="M21 12a9 9 0 1 1-6.219-8.56"/>
            """
        case .brushCleaning:
            return """
            <path d="m16 22-1-4"/>
            <path d="M19 14a1 1 0 0 0 1-1v-1a2 2 0 0 0-2-2h-3a1 1 0 0 1-1-1V4a2 2 0 0 0-4 0v5a1 1 0 0 1-1 1H6a2 2 0 0 0-2 2v1a1 1 0 0 0 1 1"/>
            <path d="M19 14H5l-1.973 6.767A1 1 0 0 0 4 22h16a1 1 0 0 0 .973-1.233z"/>
            <path d="m8 22 1-4"/>
            """
        case .fileSearch:
            return """
            <path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"/>
            <path d="M14 2v5a1 1 0 0 0 1 1h5"/>
            <circle cx="11.5" cy="14.5" r="2.5"/>
            <path d="M13.3 16.3 15 18"/>
            """
        case .pencil:
            return """
            <path d="m16 3 5 5L8 21l-5 1 1-5Z M14 5l5 5"/>
            """
        case .smile:
            return """
            <circle cx="12" cy="12" r="9"/><path d="M8 14s1 3 4 3 4-3 4-3M9 9h.01M15 9h.01"/>
            """
        case .briefcase:
            return """
            <rect x="3" y="7" width="18" height="14" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12h18M12 10v4"/>
            """
        case .alignLeft:
            return """
            <path d="M4 6h16M4 10h10M4 14h16M4 18h10"/>
            """
        case .list:
            return """
            <path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>
            """
        case .listChecks:
            return """
            <path d="M13 6h8M13 12h8M13 18h8M3 6l2 2 4-4M3 18l2 2 4-4"/>
            """
        case .table:
            return """
            <rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 9v12"/>
            """
        case .sparkleFilled:
            return """
            <path d="m12 2-2.5 7.5L2 12l7.5 2.5L12 22l2.5-7.5L22 12l-7.5-2.5Z" fill="black" stroke="none"/>
            """
        case .sparkles:
            return """
            <path d="m12 3-1.9 5.8a2 2 0 0 1-1.3 1.3L3 12l5.8 1.9a2 2 0 0 1 1.3 1.3L12 21l1.9-5.8a2 2 0 0 1 1.3-1.3L21 12l-5.8-1.9a2 2 0 0 1-1.3-1.3Z"/>
            """
        case .arrowRight:
            return """
            <path d="M5 12h14"/>
            <path d="m12 5 7 7-7 7"/>
            """
        case .sliders:
            return """
            <line x1="4" x2="4" y1="21" y2="14"/>
            <line x1="4" x2="4" y1="10" y2="3"/>
            <line x1="12" x2="12" y1="21" y2="12"/>
            <line x1="12" x2="12" y1="8" y2="3"/>
            <line x1="20" x2="20" y1="21" y2="16"/>
            <line x1="20" x2="20" y1="12" y2="3"/>
            <line x1="1" x2="7" y1="14" y2="14"/>
            <line x1="9" x2="15" y1="8" y2="8"/>
            <line x1="17" x2="23" y1="16" y2="16"/>
            """
        case .folder:
            return """
            <path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>
            """
        case .plus:
            return """
            <path d="M5 12h14"/>
            <path d="M12 5v14"/>
            """
        case .xmark, .x:
            return """
            <path d="M18 6 6 18"/>
            <path d="m6 6 12 12"/>
            """
        case .waveform:
            return """
            <path d="M2 10v4"/>
            <path d="M6 7v10"/>
            <path d="M10 3v18"/>
            <path d="M14 7v10"/>
            <path d="M18 10v4"/>
            <path d="M22 10v4"/>
            """
        case .activity:
            return """
            <path d="M22 12h-4l-3 9L9 3l-3 9H2"/>
            """
        case .target:
            return """
            <circle cx="12" cy="12" r="10"/>
            <circle cx="12" cy="12" r="6"/>
            <circle cx="12" cy="12" r="2"/>
            """
        case .uploadCloud:
            return """
            <path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"/>
            <path d="M12 12v9"/>
            <path d="m16 16-4-4-4 4"/>
            """
        case .globe:
            return """
            <circle cx="12" cy="12" r="10"/>
            <path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/>
            <path d="M2 12h20"/>
            """
        case .shield:
            return """
            <path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>
            """
        case .palette:
            return """
            <circle cx="13.5" cy="6.5" r="1" fill="black"/>
            <circle cx="17.5" cy="10.5" r="1" fill="black"/>
            <circle cx="8.5" cy="7.5" r="1" fill="black"/>
            <circle cx="6.5" cy="12.5" r="1" fill="black"/>
            <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z"/>
            """
        case .wrench:
            return """
            <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>
            """
        case .userRound:
            return """
            <circle cx="12" cy="8" r="5"/>
            <path d="M20 21a8 8 0 0 0-16 0"/>
            """
        case .slidersHorizontal:
            return """
            <line x1="21" x2="14" y1="4" y2="4"/>
            <line x1="10" x2="3" y1="4" y2="4"/>
            <line x1="21" x2="12" y1="12" y2="12"/>
            <line x1="8" x2="3" y1="12" y2="12"/>
            <line x1="21" x2="16" y1="20" y2="20"/>
            <line x1="12" x2="3" y1="20" y2="20"/>
            <line x1="14" x2="14" y1="2" y2="6"/>
            <line x1="8" x2="8" y1="10" y2="14"/>
            <line x1="16" x2="16" y1="18" y2="22"/>
            """
        }
    }
}
