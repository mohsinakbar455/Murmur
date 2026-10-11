import MurmurDictionary
import SwiftUI

struct PersonalizationView: View {
    private enum Tab: String, CaseIterable {
        case snippets = "Snippets", dictionary = "Dictionary", styles = "Styles", memory = "Memory"
    }
    @State private var selectedTab: Tab = .dictionary
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var isAdding = false
    @State private var editing: DictionaryEntry?
    private var snippets: [DictionaryEntry] { store.filtered(by: query).filter { $0.kind == .snippet } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                PageHeader(title: "Personalization", subtitle: "Teach Murmur your words, writing style, and preferences.") {
                    if selectedTab == .snippets {
                        MurmurButton("Add Snippet", lucide: .plus, style: .primary) { isAdding = true }
                    }
                }
                HStack(spacing: DS.Space.wide) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Button { selectedTab = tab } label: {
                            Text(tab.rawValue.uppercased()).font(DS.Font.label)
                                .foregroundStyle(selectedTab == tab ? DS.Color.textPrimary : DS.Color.textSecondary)
                                .padding(.vertical, DS.Space.base)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(selectedTab == tab ? DS.Color.accent : .clear).frame(height: 2)
                                }
                        }.buttonStyle(.plain).accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                    Spacer()
                }
                switch selectedTab {
                case .dictionary: LearnedDictionaryView()
                case .styles: WritingPersonalizationView(mode: .styles)
                case .memory: WritingPersonalizationView(mode: .memory)
                case .snippets:
                    Text("Say a shorthand and Murmur expands it into saved text.")
                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    TextField("Search snippets…", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                    if snippets.isEmpty {
                        EmptyStateView(lucide: .fileText, title: query.isEmpty ? "No snippets yet" : "No matches",
                            message: "Create a memorable spoken shortcut for text you type repeatedly.", actionTitle: nil)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(snippets) { entry in
                                PersonalizationRow(entry: entry, onEdit: { editing = entry }, onToggle: {
                                    var updated = entry; updated.isEnabled.toggle(); store.update(updated)
                                }, onDelete: { store.delete(entry) })
                                if entry.id != snippets.last?.id { Divider() }
                            }
                        }.background(DS.Color.card).clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
                    }
                }
            }.padding(DS.Space.panel)
        }.background(DS.Color.canvas)
        .sheet(isPresented: $isAdding) { SnippetEditor(entry: nil) { store.add($0) } }
        .sheet(item: $editing) { entry in SnippetEditor(entry: entry) { store.update($0) } }
    }
}

struct FillerWordsSettingsView: View {
    @State private var store = FillerWordStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            Toggle("Remove filler words", isOn: Binding(get: { store.isEnabled }, set: { store.setEnabled($0) }))
                .toggleStyle(.switch).font(DS.Font.bodyEmphasis)
            Text("Remove complete words such as “um” and “uh” when automatic formatting is on.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            FillerWordTagField(words: store.words, existingWords: store.words,
                onAdd: { _ = store.add($0) }, onDelete: { store.delete($0) })
            Button("Reset filler words to defaults") { store.resetToDefaults() }.font(DS.Font.caption)
        }.padding(DS.Space.roomy)
    }
}

// MARK: - Entry row

private struct PersonalizationRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.base) {
            entryContent
                .opacity(entry.isEnabled ? 1 : 0.55)

            Spacer(minLength: DS.Space.base)

            HStack(spacing: DS.Space.tight) {
                PersonalizationActionButton("Edit", action: onEdit)
                PersonalizationActionButton(entry.isEnabled ? "Disable" : "Enable", action: onToggle)
                PersonalizationActionButton("Delete entry", icon: .trash2, action: onDelete)
            }
        }
        .padding(.horizontal, DS.Space.roomy)
        .frame(minHeight: DS.Layout.personalizationRowMinHeight)
        .accessibilityElement(children: .contain)
        .accessibilityValue(entry.isEnabled ? "Enabled" : "Disabled")
    }

    @ViewBuilder
    private var entryContent: some View {
        if entry.kind == .snippet {
            Text(entry.hear)
                .font(DS.Font.counter)
                .foregroundStyle(DS.Color.textPrimary)
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.tight)
                .background(DS.Color.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))

            LucideIcon(.arrowRight, size: DS.Material.iconSizeSmall)
                .foregroundStyle(DS.Color.textTertiary)

            Text(entry.write)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
        } else if entry.kind == .correction {
            Text(entry.hear)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)

            LucideIcon(.arrowRight, size: DS.Material.iconSizeSmall)
                .foregroundStyle(DS.Color.textTertiary)

            Text(entry.write)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.textPrimary)
        } else {
            Text(entry.write)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.textPrimary)
        }

        if !entry.isEnabled {
            Text("Disabled")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }
}

// MARK: - Filler word tags

/// A compact, inline vocabulary field. Its content is deliberately presented as one
/// sentence-like collection rather than a set of independent settings rows.
struct FillerWordTagField: View {
    let words: [String]
    let existingWords: [String]
    let onAdd: (String) -> Void
    let onDelete: (String) -> Void

    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    private var normalizedDraft: String? {
        FillerWordFilter.normalize(draft)
    }

    private var isDuplicate: Bool {
        guard let normalizedDraft else { return false }
        return existingWords.contains {
            $0.caseInsensitiveCompare(normalizedDraft) == .orderedSame
        }
    }

    private var canAdd: Bool {
        normalizedDraft != nil && !isDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            WrappingTagLayout(spacing: DS.Space.snug, lineSpacing: DS.Space.snug) {
                ForEach(words, id: \.self) { word in
                    FillerWordTag(word: word) {
                        onDelete(word)
                    }
                }

                HStack(spacing: DS.Space.tight) {
                    TextField("Add a word or phrase", text: $draft)
                        .textFieldStyle(.plain)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                        .focused($isInputFocused)
                        .onSubmit(addDraft)
                        .frame(minWidth: DS.Layout.personalizationTagInputMinWidth)

                    Button(action: addDraft) {
                        LucideIcon(.plus, size: DS.Material.iconSizeSmall)
                            .foregroundStyle(canAdd ? DS.Color.textPrimary : DS.Color.textTertiary)
                            .frame(
                                width: DS.Layout.personalizationTagActionSize,
                                height: DS.Layout.personalizationTagActionSize
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .help("Add filler word")
                    .accessibilityLabel("Add filler word")
                }
                .padding(.leading, DS.Space.snug)
                .padding(.trailing, DS.Space.tight)
                .padding(.vertical, DS.Space.tight)
                .background(DS.Color.card)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                }
            }

            if isDuplicate {
                Text("That filler word is already included.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            } else {
                Text("Type a word or short phrase, then press Return to add it.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(DS.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        }
    }

    private func addDraft() {
        guard let normalizedDraft, canAdd else { return }
        onAdd(normalizedDraft)
        draft = ""
        isInputFocused = true
    }
}

private struct FillerWordTag: View {
    let word: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.tight) {
            Text(word)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.textPrimary)

            Button(action: onDelete) {
                LucideIcon(.xmark, size: DS.Material.iconSizeSmall)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(word)")
            .accessibilityLabel("Remove \(word)")
        }
        .padding(.horizontal, DS.Space.snug)
        .padding(.vertical, DS.Space.tight)
        .background(DS.Color.card)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        }
    }
}

private struct WrappingTagLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maximumWidth = proposal.width ?? .greatestFiniteMagnitude
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maximumWidth {
                totalHeight += rowHeight + lineSpacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: proposal.width ?? rowWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + spacing + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            if x > bounds.minX {
                x += spacing
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Snippet editor

private struct SnippetEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shortcut: String
    @State private var expansion: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _shortcut = State(initialValue: entry?.hear ?? "")
        _expansion = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        let singleLineExpansion = expansion
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: .snippet,
            write: singleLineExpansion,
            hear: shortcut.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }
    private var isValid: Bool { !draft.hear.isEmpty && !draft.write.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text(entry == nil ? "New Snippet" : "Edit Snippet")
                    .font(DS.Font.sectionTitle)
                    .foregroundStyle(DS.Color.textPrimary)

                Text("Murmur expands the spoken shortcut after transcription.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text("Spoken shortcut")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.textSecondary)
                TextField("e.g. slash intro", text: $shortcut)
                    .textFieldStyle(.roundedBorder)
                    .tint(DS.Color.accent)
            }

            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text("Expand to")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.textSecondary)
                TextField("Text Murmur should insert", text: $expansion, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DS.Font.body)
                    .padding(DS.Space.snug)
                    .lineLimit(4...8)
                    .frame(minHeight: DS.Layout.personalizationExpansionMinHeight)
                    .background(DS.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                    }
                    .tint(DS.Color.accent)
            }

            ForEach(warnings) { warning in
                PersonalizationWarning(message: warning.message)
            }

            Divider().overlay(DS.Color.borderSubtle)

            HStack(spacing: DS.Space.base) {
                Spacer()
                MurmurButton("Cancel", style: .subtle) { dismiss() }
                MurmurButton("Save Snippet", lucide: .check, style: .primary) {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .padding(DS.Space.panel)
        .frame(width: DS.Layout.personalizationEditorWidth)
        .background(DS.Color.cardElevated)
    }
}

private struct PersonalizationWarning: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.snug) {
            LucideIcon(.alertCircle, size: DS.Material.iconSizeBase)
                .foregroundStyle(DS.Color.textSecondary)
            Text(message)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
    }
}
