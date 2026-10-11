import AppKit
import MurmurDictionary
import SwiftUI

struct LearnedDictionaryView: View {
    @State private var store = LearnedTermStore.shared
    @State private var query = ""
    @State private var adding = false
    @State private var editing: LearnedTerm?
    private var filtered: [LearnedTerm] {
        store.terms.filter { query.isEmpty || $0.canonical.localizedStandardContains(query) || $0.aliases.contains { $0.localizedStandardContains(query) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("Dictionary").font(DS.Font.sectionTitle)
                    Text("Names and terms, written the way you want.").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                MurmurButton("Add Word", lucide: .plus, style: .primary) { adding = true }
                    .disabled(store.isReadOnly)
            }
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                HStack {
                    Text("Smart Learning").font(DS.Font.bodyEmphasis)
                    Spacer()
                    Picker("Smart Learning", selection: Binding(get: { store.mode }, set: { store.setMode($0) })) {
                        ForEach(SmartLearningMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(maxWidth: 220).disabled(store.isReadOnly)
                }
                Text("Correct a name or term after dictation and Murmur can remember it.")
                    .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                Text("Review suggestions here. Learning runs locally with Qwen in supported text fields.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                if WritingModelManager.shared.selectedModelURL == nil, store.mode != .off {
                    Text("Select a downloaded Qwen model in Models → Writing & cleanup to learn spelling corrections.")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.warningAmber)
                }
            }
            if let error = store.errorMessage {
                Text(error).foregroundStyle(DS.Color.warningAmber).font(DS.Font.body).textSelection(.enabled)
            } else if let action = store.lastAction {
                HStack {
                    Text(action).font(DS.Font.body).accessibilityLabel(action)
                    Spacer()
                    if store.canUndo { Button("Undo") { store.undo() } }
                }
            }
            if !store.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.base) {
                    Text("Suggestions (\(store.suggestions.count))").font(DS.Font.bodyEmphasis)
                    ForEach(store.suggestions) { term in
                        HStack(alignment: .top) {
                            termLabel(term)
                            Spacer()
                            Button("Learn") { store.accept(term) }.disabled(store.isReadOnly)
                            Button("Dismiss") { store.dismissSuggestion(term) }.disabled(store.isReadOnly)
                        }
                    }
                }.padding(DS.Space.roomy).background(DS.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            }
            TextField("Search names, terms and mishearings…", text: $query)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 380).accessibilityLabel("Search dictionary")
            if filtered.isEmpty {
                EmptyStateView(lucide: .bookOpen, title: query.isEmpty ? "Your words belong here" : "No matching terms",
                    message: query.isEmpty ? "Add a name and its possible mishearings, or correct a dictation to suggest a term." : "Try another spelling or mishearing.", actionTitle: nil)
            } else {
                VStack(spacing: 0) {
                    ForEach(filtered) { term in
                        HStack(alignment: .center, spacing: DS.Space.base) {
                            termLabel(term).opacity(term.isEnabled ? 1 : 0.55)
                            Spacer(minLength: DS.Space.base)
                            PersonalizationActionButton("Edit") { editing = term }
                            PersonalizationActionButton(term.isEnabled ? "Disable" : "Enable") { store.toggle(term) }
                            PersonalizationActionButton("Delete \(term.canonical)", icon: .trash2) { store.delete(term) }
                        }.padding(DS.Space.roomy).disabled(store.isReadOnly)
                        if term.id != filtered.last?.id { Divider().overlay(DS.Color.borderSubtle) }
                    }
                }.background(DS.Color.card).clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            }
            Text("\(store.terms.count) terms").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            if !PersonalizationStore.shared.examples.isEmpty
                || (PersonalizationStore.shared.lastAction == "Correction forgotten" && PersonalizationStore.shared.canUndo) {
                SavedCorrectionArchive(learning: store)
            }
        }
        .foregroundStyle(DS.Color.textPrimary)
        .sheet(isPresented: $adding) { LearnedTermEditor(term: nil) }
        .sheet(item: $editing) { LearnedTermEditor(term: $0) }
    }
    private func termLabel(_ term: LearnedTerm) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text(term.canonical).font(DS.Font.bodyEmphasis).textSelection(.enabled)
            if !term.aliases.isEmpty {
                Text("Heard as: \(term.aliases.joined(separator: ", "))").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
            }
            Text("\(term.source) · \(term.bundleID.map { PersonalizationApplications.name(for: $0) } ?? "All apps")\(term.isEnabled ? "" : " · Disabled")")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

/// A quiet archive for old full-sentence examples. It does not compete with the
/// dictionary's primary action, and every row stays aligned at any window width.
private struct SavedCorrectionArchive: View {
    @State private var personalization = PersonalizationStore.shared
    let learning: LearnedTermStore
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(DS.Motion.transition) { isExpanded.toggle() } } label: {
                HStack(spacing: DS.Space.snug) {
                    LucideIcon(isExpanded ? .chevronDown : .chevronRight, size: 16)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("Previous corrections")
                        .font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textPrimary)
                    Text("\(personalization.examples.count) saved")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(DS.Space.roomy)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous saved corrections")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Divider().overlay(DS.Color.borderSubtle)
                VStack(alignment: .leading, spacing: DS.Space.base) {
                    Text("Your older examples are kept here. Useful names and spellings appear in Dictionary after review.")
                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if personalization.lastAction == "Correction forgotten", personalization.canUndo {
                        HStack {
                            Text("Saved correction deleted").font(DS.Font.caption)
                            Button("Undo") { personalization.undoLastChange() }
                        }
                    }

                    if personalization.examples.isEmpty {
                        Text("No previous corrections remain.")
                            .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(personalization.examples) { example in
                                VStack(alignment: .leading, spacing: DS.Space.snug) {
                                    Text(example.raw)
                                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                                        .textSelection(.enabled)
                                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.snug) {
                                        LucideIcon(.arrowRight, size: 14)
                                            .foregroundStyle(DS.Color.textSecondary)
                                        Text(example.corrected)
                                            .font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textPrimary)
                                            .textSelection(.enabled)
                                    }
                                    HStack {
                                        Text(example.bundleID == nil ? "All apps" : (example.appName ?? "Selected app"))
                                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                                        Spacer()
                                        PersonalizationActionButton("Delete saved correction", icon: .trash2) {
                                            personalization.deleteExample(example.id)
                                        }
                                        .disabled(personalization.isReadOnly)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, DS.Space.base)
                                if example.id != personalization.examples.last?.id {
                                    Divider().overlay(DS.Color.borderSubtle)
                                }
                            }
                        }
                    }

                    Button(learning.isMigrating ? "Reviewing corrections…" : "Review again for spelling suggestions") {
                        Task { await learning.migrateExamples(personalization.examples, retry: true) }
                    }
                    .font(DS.Font.caption)
                    .disabled(learning.isMigrating || learning.mode == .off
                        || WritingModelManager.shared.selectedModelURL == nil)
                }
                .padding(DS.Space.roomy)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        }
    }
}

struct LearnedTermEditor: View {
    let term: LearnedTerm?
    @Environment(\.dismiss) private var dismiss
    @State private var canonical: String
    @State private var aliases: String
    @State private var bundleID: String
    @State private var store = LearnedTermStore.shared
    @State private var apps: [PersonalizationApplication] = []
    init(term: LearnedTerm?) {
        self.term = term
        _canonical = State(initialValue: term?.canonical ?? "")
        _aliases = State(initialValue: term?.aliases.joined(separator: ", ") ?? "")
        _bundleID = State(initialValue: term?.bundleID ?? "")
    }
    private var aliasWarnings: [String] {
        Array(Set(aliases.components(separatedBy: ",").flatMap {
            DictionaryWarning.check(.correction(hear: $0.trimmingCharacters(in: .whitespaces), write: canonical)).map(\.message)
        })).sorted()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            Text(term == nil ? "Teach Murmur a word" : "Edit learned word").font(DS.Font.sectionTitle)
            Text("Correct spelling").font(DS.Font.bodyEmphasis)
            TextField("e.g. Wispr Flow", text: $canonical).textFieldStyle(.roundedBorder).accessibilityLabel("Correct spelling")
            Text("Possible mishearings · optional").font(DS.Font.bodyEmphasis)
            TextField("e.g. whisper flow, whisperflow", text: $aliases).textFieldStyle(.roundedBorder).accessibilityLabel("Possible mishearings, separated by commas")
            Text("Separate mishearings with commas. Murmur will use the correct spelling above.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            ForEach(aliasWarnings, id: \.self) { warning in
                Text(warning).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Picker("Use in", selection: $bundleID) {
                Text("All apps").tag("")
                ForEach(apps) { Text($0.name).tag($0.id) }
                if !bundleID.isEmpty, !apps.contains(where: { $0.id == bundleID }) { Text(PersonalizationApplications.name(for: bundleID)).tag(bundleID) }
            }
            if let error = store.errorMessage { Text(error).font(DS.Font.caption).foregroundStyle(DS.Color.warningAmber) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                MurmurButton("Save Word", style: .primary) {
                    if store.save(id: term?.id, canonical: canonical, aliases: aliases.components(separatedBy: ","), bundleID: bundleID.isEmpty ? nil : bundleID) { dismiss() }
                }.disabled(canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isReadOnly)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(DS.Space.panel).frame(width: 520).background(DS.Color.canvas)
        .onAppear { apps = PersonalizationApplications.available(including: PersonalizationStore.shared.appRules) }
    }
}
