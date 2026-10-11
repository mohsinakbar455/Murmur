import SwiftUI

// MARK: - Modern UI Components (Lemon-inspired)

/// A modern, clean card component used throughout Murmur.
public struct MurmurCard<Content: View>: View {
    public var padding: CGFloat = DS.Space.card
    public var cornerRadius: CGFloat = DS.Radius.card
    public var elevated: Bool = false
    @ViewBuilder public var content: Content

    public init(
        padding: CGFloat = DS.Space.card,
        cornerRadius: CGFloat = DS.Radius.card,
        elevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(elevated ? DS.Color.cardElevated : DS.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
            )
            .shadow(
                color: DS.Shadow.subtle.color,
                radius: DS.Shadow.subtle.radius,
                x: DS.Shadow.subtle.x,
                y: DS.Shadow.subtle.y
            )
    }
}

/// A modern status badge with a colored indicator dot.
public struct StatusBadge: View {
    public enum Status {
        case ready
        case active
        case loading
        case downloading
        case idle
        case warning
        case error

        public var color: Color {
            switch self {
            case .ready: return DS.Color.textSecondary
            case .active: return DS.Color.accent
            case .loading, .downloading: return DS.Color.accent
            case .idle: return DS.Color.textTertiary
            case .warning: return DS.Color.warningAmber
            case .error: return DS.Color.recordRed
            }
        }
    }

    public let text: String
    public let status: Status

    public init(_ text: String, status: Status) {
        self.text = text
        self.status = status
    }

    public var body: some View {
        HStack(spacing: DS.Space.tight) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)

            Text(text)
                .font(DS.Font.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Space.snug)
        .padding(.vertical, DS.Space.tight)
        .background(DS.Color.cardElevated)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        )
    }
}

/// Modern interactive button with hover and press feedback.
public struct MurmurButton: View {
    public enum Style {
        case primary
        case secondary
        case subtle
        case danger
    }

    public let title: String
    public var icon: String? = nil
    public var lucide: LucideIcon.Name? = nil
    public var style: Style = .secondary
    public var isSelected: Bool = false
    public var height: CGFloat? = nil
    public var action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        icon: String? = nil,
        lucide: LucideIcon.Name? = nil,
        style: Style = .secondary,
        isSelected: Bool = false,
        height: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.lucide = lucide
        self.style = style
        self.isSelected = isSelected
        self.height = height
        self.action = action
    }

    private var backgroundColor: Color {
        if isSelected {
            return style == .primary ? DS.Color.accent : DS.Color.cardSelected
        }
        switch style {
        case .primary:
            return DS.Color.accent
        case .secondary:
            return isHovering ? DS.Color.hover : DS.Color.card
        case .subtle:
            return isHovering ? DS.Color.hover : Color.clear
        case .danger:
            return isHovering ? DS.Color.recordRed.opacity(0.2) : DS.Color.recordRed.opacity(0.1)
        }
    }

    private var foregroundColor: Color {
        if isSelected && style == .primary {
            return DS.Color.textOnAccent
        }
        switch style {
        case .primary: return DS.Color.textOnAccent
        case .secondary, .subtle: return DS.Color.textPrimary
        case .danger: return DS.Color.recordRed
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.snug) {
                if let lucide {
                    LucideIcon(lucide, size: style == .primary ? 16 : 14)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(style == .primary ? DS.Font.bodyEmphasis : DS.Font.body)
            }
            .padding(.horizontal, style == .primary ? DS.Space.roomy : DS.Space.base)
            .padding(.vertical, height == nil ? DS.Space.snug : 0)
            .frame(height: height)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(isSelected ? DS.Color.accent : DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
            )
        }
        .buttonStyle(MurmurButtonInteractionStyle())
        .scaleEffect(style == .primary && isHovering && isEnabled && !reduceMotion ? 1.045 : 1)
        .shadow(color: style == .primary && isHovering && isEnabled ? DS.Color.accent.opacity(0.22) : .clear,
                radius: 7, x: 0, y: 3)
        .animation(reduceMotion ? nil : DS.Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct MurmurButtonInteractionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed && isEnabled
                    ? DS.Material.buttonPressedScale
                    : 1
            )
            .animation(
                configuration.isPressed ? DS.Motion.press : DS.Motion.release,
                value: configuration.isPressed
            )
    }
}

/// Native macOS Visual Effect view for Liquid Glass blurs.
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .sidebar
    public var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    public var state: NSVisualEffectView.State = .active

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Liquid Glass container surface for floating controls, HUDs, and sidebar elements.
public struct LiquidGlassSurface<Content: View>: View {
    public var cornerRadius: CGFloat = DS.Radius.card
    public var padding: CGFloat = DS.Space.base
    @ViewBuilder public var content: Content

    public init(
        cornerRadius: CGFloat = DS.Radius.card,
        padding: CGFloat = DS.Space.base,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background {
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.Color.borderGlass, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.20), radius: 12, y: 4)
    }
}

/// Compact modern microphone level indicator.
public struct ModernLevelMeter: View {
    public let level: Float
    public let isActive: Bool

    public init(level: Float, isActive: Bool) {
        self.level = level
        self.isActive = isActive
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<14, id: \.self) { index in
                let threshold = Float(index) / 14.0
                let isLit = isActive && level > threshold
                let color = index >= 11 ? DS.Color.recordRed : (index >= 8 ? DS.Color.warningAmber : DS.Color.successGreen)

                RoundedRectangle(cornerRadius: 1)
                    .fill(isLit ? color : DS.Color.borderSubtle)
                    .frame(width: 3, height: CGFloat(8 + index * 1))
            }
        }
        .frame(height: 22)
        .padding(.horizontal, DS.Space.snug)
        .padding(.vertical, 4)
        .background(DS.Color.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}

// MARK: - Compatibility Wrappers for Existing Views

/// Compatibility wrapper rendering a modern card instead of brushed metal.
public struct BrushedPanel: View {
    public var radius: CGFloat = DS.Radius.card

    public init(radius: CGFloat = DS.Radius.card) {
        self.radius = radius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DS.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
            )
    }
}

public struct Well<Content: View>: View {
    public var radius: CGFloat = DS.Radius.card
    @ViewBuilder public var content: Content

    public init(radius: CGFloat = DS.Radius.card, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        content
            .background(DS.Color.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
            )
    }
}

public struct DeckWindow<Content: View>: View {
    public var radius: CGFloat = DS.Radius.card
    @ViewBuilder public var content: Content

    public init(radius: CGFloat = DS.Radius.card, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        content
            .background(DS.Color.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
            )
    }
}

public struct Silkscreen: View {
    public let text: String
    public var large: Bool = false
    public var color: Color = DS.Color.textSecondary

    public init(text: String, large: Bool = false, color: Color = DS.Color.textSecondary) {
        self.text = text
        self.large = large
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(large ? DS.Font.cardTitle : DS.Font.label)
            .foregroundStyle(color)
    }
}

public struct Screw: View {
    public init() {}
    public var body: some View {
        // Decorative cassette screws removed per brief
        EmptyView()
    }
}

public struct Vents: View {
    public var count: Int = 0
    public init(count: Int = 0) { self.count = count }
    public var body: some View {
        // Decorative vents removed per brief
        EmptyView()
    }
}

public struct Lamp: View {
    public let color: Color
    public let isLit: Bool
    public var size: CGFloat = 8

    public init(color: Color, isLit: Bool, size: CGFloat = 8) {
        self.color = color
        self.isLit = isLit
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(isLit ? color : DS.Color.textTertiary.opacity(0.3))
            .frame(width: size, height: size)
    }
}

public struct SearchField: View {
    @Binding public var text: String
    public let placeholder: String

    public init(text: Binding<String>, placeholder: String) {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: DS.Space.snug) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Color.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background(DS.Color.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        )
    }
}

public struct EmptyPanel: View {
    public let label: String
    public let detail: String

    public init(label: String, detail: String) {
        self.label = label
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: DS.Space.snug) {
            Text(label)
                .font(DS.Font.cardTitle)
                .foregroundStyle(DS.Color.textSecondary)
            Text(detail)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.roomy)
    }
}

public struct TransportKey: View {
    public let title: String
    public var systemImage: String? = nil
    public var isEngaged: Bool = false
    public var engagedColor: Color = DS.Color.accent
    public var action: () -> Void

    public init(
        title: String,
        systemImage: String? = nil,
        isEngaged: Bool = false,
        engagedColor: Color = DS.Color.accent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEngaged = isEngaged
        self.engagedColor = engagedColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.tight) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(DS.Font.bodyEmphasis)
            }
            .padding(.horizontal, DS.Space.base)
            .padding(.vertical, DS.Space.snug)
            .background(isEngaged ? DS.Color.cardSelected : DS.Color.card)
            .foregroundStyle(isEngaged ? DS.Color.textPrimary : DS.Color.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(isEngaged ? DS.Color.accent : DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}

public struct VUMeter: View {
    public let level: Float
    public let isActive: Bool

    public init(level: Float, isActive: Bool) {
        self.level = level
        self.isActive = isActive
    }

    public var body: some View {
        ModernLevelMeter(level: level, isActive: isActive)
    }
}

public struct Readout: View {
    public let text: String
    public var large: Bool = false

    public init(text: String, large: Bool = false) {
        self.text = text
        self.large = large
    }

    public var body: some View {
        Text(text)
            .font(large ? DS.Font.counterLarge : DS.Font.counter)
            .foregroundStyle(DS.Color.textPrimary)
    }
}
