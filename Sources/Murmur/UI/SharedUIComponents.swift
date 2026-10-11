import SwiftUI
import AppKit

// MARK: - Page Header

/// Standardized page header used across all primary views in Murmur.
/// Provides consistent margins, hierarchy, and aligned trailing actions.
struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text(title)
                    .font(DS.Font.pageTitle)
                    .foregroundStyle(DS.Color.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            Spacer()

            actions
        }
    }
}

/// Compact actions used beside personalization entries and saved preferences.
struct PersonalizationActionButton: View {
    let title: String
    var icon: LucideIcon.Name? = nil
    let action: () -> Void

    init(_ title: String, icon: LucideIcon.Name? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    private var isHighlighted: Bool { isEnabled && (isHovering || isFocused) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.tight) {
                if let icon {
                    LucideIcon(icon, size: DS.Material.iconSizeSmall)
                } else {
                    Text(title)
                        .font(DS.Font.caption)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(isHighlighted ? DS.Color.textOnAccent : DS.Color.textPrimary)
            .frame(minWidth: icon == nil ? 0 : 28, minHeight: 28)
            .padding(.horizontal, icon == nil ? DS.Space.snug : 0)
            .background(isHighlighted ? DS.Color.accent : DS.Color.cardElevated,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(isHighlighted ? DS.Color.accent : DS.Color.borderSubtle,
                                  lineWidth: DS.Border.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .opacity(isEnabled ? 1 : 0.5)
        .scaleEffect(isHovering && isEnabled && !reduceMotion ? 1.045 : 1)
        .animation(reduceMotion ? nil : DS.Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .help(title)
    }
}

// MARK: - Shortcut Badge

/// Compact, accessible shortcut badge displaying keycap tokens.
struct ShortcutBadge: View {
    let binding: ShortcutBinding
    var action: (() -> Void)? = nil

    init(_ binding: ShortcutBinding, action: (() -> Void)? = nil) {
        self.binding = binding
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) {
                badgeContent
            }
            .buttonStyle(.plain)
            .help("Change dictation shortcut (\(binding.displayName))")
            .accessibilityLabel("Change dictation shortcut, currently \(binding.displayName)")
        } else {
            badgeContent
        }
    }

    private var badgeContent: some View {
        HStack(spacing: 3) {
            ForEach(binding.keycapTokens, id: \.self) { token in
                Text(token)
                    .font(DS.Font.counter)
                    .foregroundStyle(DS.Color.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DS.Color.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                    )
            }
        }
        .padding(.horizontal, DS.Space.snug)
        .padding(.vertical, 4)
        .background(DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        )
    }
}

// MARK: - History / Recent Transcript Row

/// Standardized transcript row for dictation runs.
/// Prioritizes transcript text over metadata, provides quick accessible copy with feedback.
struct HistoryRunRow: View {
    let run: DictationRun
    var onDelete: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var didCopy = false

    init(run: DictationRun, onDelete: (() -> Void)? = nil) {
        self.run = run
        self.onDelete = onDelete
    }

    public var body: some View {
        MurmurCard(padding: DS.Space.card) {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                // Transcript text takes visual priority
                Text(run.text)
                    .font(DS.Font.bodyLarge)
                    .foregroundStyle(DS.Color.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                // Secondary metadata row & actions
                HStack(spacing: DS.Space.snug) {
                    StatusBadge(run.engine, status: .idle)

                    Text(String(format: "%.2fs latency", run.processSeconds))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)

                    Text("•")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)

                    Text(String(format: "%.1fs audio", run.audioSeconds))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)

                    Spacer()

                    Text(run.date, style: .time)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)

                    // Copy action button
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(run.text, forType: .string)
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            didCopy = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                            Text(didCopy ? "Copied" : "Copy")
                                .font(DS.Font.caption)
                        }
                        .padding(.horizontal, DS.Space.snug)
                        .padding(.vertical, 3)
                        .background(DS.Color.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip)
                                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Copy transcript to clipboard")

                    // Optional delete button
                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.Color.textTertiary)
                                .padding(5)
                        }
                        .buttonStyle(.plain)
                        .help("Delete this transcript")
                    }
                }
            }
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Settings Row

/// Reusable settings row component with title & subtitle on left, control on right.
struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    @ViewBuilder var control: Control

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text(title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)

                if let description {
                    Text(description)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: DS.Space.wide)

            control
        }
    }
}

// MARK: - Empty State

/// Standard empty state container.
struct EmptyStateView: View {
    var icon: String? = nil
    var lucide: LucideIcon.Name? = nil
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    init(
        icon: String? = nil,
        lucide: LucideIcon.Name? = nil,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.lucide = lucide
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        MurmurCard(padding: DS.Space.panel) {
            VStack(spacing: DS.Space.base) {
                if let lucide {
                    LucideIcon(lucide, size: 36)
                        .foregroundStyle(DS.Color.textTertiary)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundStyle(DS.Color.textTertiary)
                }

                Text(title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)

                Text(message)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                if let actionTitle, let action {
                    MurmurButton(actionTitle, style: .primary, action: action)
                        .padding(.top, DS.Space.snug)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
