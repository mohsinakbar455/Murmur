import AppKit
import MurmurDictionary
import SwiftUI

/// Additional tabs inside Murmur's existing Personalization surface.
struct WritingPersonalizationView: View {
    enum Mode: Equatable { case styles, memory }
    private enum StylePage: String, CaseIterable { case tones = "Tones", apps = "Apps" }
    let mode: Mode

    @State private var store = PersonalizationStore.shared
    @State private var applications: [PersonalizationApplication] = []
    @State private var selectedAppID = ""
    @State private var selectedStyleID = "clean"
    @State private var previewStyleID = ""
    @State private var stylePage: StylePage = .tones
    @State private var isAddingAppStyle = false
    @State private var memoryText = ""
    @State private var memoryAppID = ""
    @State private var editingMemoryID: UUID?
    @State private var settings = Settings.shared
    @FocusState private var isMemoryEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            feedback
            if mode == .styles {
                styleNavigation
                if stylePage == .tones { styleSelection } else { appStyles }
            } else if mode == .memory {
                memoryIntroduction
                memoryEditor
                savedMemories
            }
        }
        .onAppear {
            applications = PersonalizationApplications.available(including: store.appRules)
            if previewStyleID.isEmpty { previewStyleID = store.defaultStyleID }
            if mode == .memory, editingMemoryID == nil,
               let first = store.memories.first(where: { $0.bundleID == nil }) {
                loadMemory(first, focus: false)
            }
        }
        .onDisappear { if mode == .memory { persistMemory() } }

    }

    @ViewBuilder
    private var feedback: some View {
        if let error = store.errorMessage {
            HStack(alignment: .top, spacing: DS.Space.base) {
                LucideIcon(.circleAlert, size: 18).foregroundStyle(DS.Color.warningAmber)
                Text(error).font(DS.Font.body).foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if store.isReadOnly {
                    Button("Show File") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
                    Button("Reload") { store.reload() }
                }
            }
            .writingSurface()
            .accessibilityElement(children: .contain)
        } else if let action = store.lastAction {
            HStack {
                LucideIcon(.check, size: 15).foregroundStyle(DS.Color.accent)
                Text(action).font(DS.Font.body).foregroundStyle(DS.Color.textPrimary)
                Spacer()
                if store.canUndo {
                    Button("Undo") { store.undoLastChange() }
                        .accessibilityLabel("Undo last personalization change")
                }
            }
        }
    }

    private var styleNavigation: some View {
        HStack(spacing: DS.Space.wide) {
            ForEach(StylePage.allCases, id: \.self) { page in
                Button { stylePage = page } label: {
                    Text(page.rawValue)
                        .font(DS.Font.bodyEmphasis)
                        .foregroundStyle(stylePage == page ? DS.Color.textPrimary : DS.Color.textSecondary)
                        .padding(.vertical, DS.Space.snug)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(stylePage == page ? DS.Color.accent : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(stylePage == page ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { DS.Color.borderSubtle.frame(height: 1) }
    }

    private var styleSelection: some View {
        VStack(alignment: .leading, spacing: DS.Space.card) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 215), spacing: DS.Space.base)], spacing: DS.Space.base) {
                ForEach(WritingStyle.builtIns) { style in styleCard(style) }
            }

            if let style = WritingStyle.find(previewStyleID) {
                VStack(alignment: .leading, spacing: DS.Space.card) {
                    HStack(alignment: .top, spacing: DS.Space.base) {
                        VStack(alignment: .leading, spacing: DS.Space.tight) {
                            Text(style.name).font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
                            Text(style.summary).font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                        }
                        Spacer(minLength: DS.Space.base)
                        if store.defaultStyleID == style.id {
                            Text("Default style")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Color.textOnAccent)
                                .padding(.horizontal, DS.Space.base)
                                .padding(.vertical, DS.Space.snug)
                                .background(DS.Color.accent, in: Capsule())
                        } else {
                            MurmurButton("Set as default", style: .primary) {
                                store.setDefaultStyle(style.id)
                            }
                            .disabled(store.isReadOnly)
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Space.snug) {
                        Text("EXAMPLE OUTPUT")
                            .font(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                        Text(style.sample)
                            .font(DS.Font.bodyLarge).foregroundStyle(DS.Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.card)
                    .background(DS.Color.canvas, in: RoundedRectangle(cornerRadius: DS.Radius.card))

                    Text("Styles apply when smart cleanup is on. Examples show the same thought; names, numbers and meaning stay intact.")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
                .padding(DS.Space.card)
                .background(DS.Color.card, in: RoundedRectangle(cornerRadius: DS.Radius.cardLarge))
            }
        }
    }

    private func styleCard(_ style: WritingStyle) -> some View {
        let isSelected = previewStyleID == style.id
        let isDefault = store.defaultStyleID == style.id
        return Button { previewStyleID = style.id } label: {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                HStack(alignment: .top, spacing: DS.Space.tight) {
                    Text(style.name).font(DS.Font.cardTitleLarge).foregroundStyle(DS.Color.textPrimary)
                    Spacer(minLength: 0)
                    if isDefault {
                        Text("Default")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textOnAccent)
                            .padding(.horizontal, DS.Space.snug)
                            .padding(.vertical, DS.Space.tight)
                            .background(DS.Color.accent, in: Capsule())
                    }
                }
                Text(style.summary)
                    .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(DS.Space.roomy)
            .background(isSelected ? DS.Color.cardSelected : DS.Color.card,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .strokeBorder(isSelected ? DS.Color.accent : DS.Color.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.name). \(style.summary)")
        .accessibilityValue([isSelected ? "Selected" : nil, isDefault ? "Default style" : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Show style example and default option")
    }

    private var appStyles: some View {
        VStack(alignment: .leading, spacing: DS.Space.card) {
            HStack(alignment: .top, spacing: DS.Space.base) {
                heading("Styles by app", detail: "Give an app its own style. Other apps use your default.")
                Spacer(minLength: DS.Space.base)
                MurmurButton(isAddingAppStyle ? "Close" : "Add app style", style: .primary) {
                    isAddingAppStyle.toggle()
                }
                    .disabled(store.isReadOnly)
            }
            if store.appRules.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.snug) {
                    Text("No app styles yet")
                        .font(DS.Font.cardTitleLarge).foregroundStyle(DS.Color.textPrimary)
                    Text("All apps currently use \(WritingStyle.find(store.defaultStyleID)?.name ?? "Clean"). Add a style when you want one app to sound different.")
                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .writingSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(store.appRules) { rule in
                        HStack(spacing: DS.Space.base) {
                            appLabel(id: rule.bundleID, name: rule.appName)
                            Spacer(minLength: DS.Space.base)
                            Picker("Style for \(rule.appName)", selection: Binding(
                                get: { rule.styleID },
                                set: { store.setAppRule(bundleID: rule.bundleID, appName: rule.appName, styleID: $0) }
                            )) { styleOptions }
                            .labelsHidden().frame(width: 160)
                            PersonalizationActionButton("Remove style for \(rule.appName)", icon: .trash2) {
                                store.deleteAppRule(bundleID: rule.bundleID)
                            }
                        }
                        .padding(.vertical, DS.Space.base)
                        if rule.id != store.appRules.last?.id { Divider().overlay(DS.Color.borderSubtle) }
                    }
                }
                .writingSurface()
                .disabled(store.isReadOnly)
            }
            if isAddingAppStyle {
                VStack(alignment: .leading, spacing: DS.Space.roomy) {
                    Text("New app style").font(DS.Font.cardTitleLarge).foregroundStyle(DS.Color.textPrimary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DS.Space.base) {
                            appPicker("App", selection: $selectedAppID, includesAllApps: false)
                            Picker("Writing style", selection: $selectedStyleID) { styleOptions }
                                .frame(width: 160)
                        }
                        VStack(alignment: .leading, spacing: DS.Space.base) {
                            appPicker("App", selection: $selectedAppID, includesAllApps: false)
                            Picker("Writing style", selection: $selectedStyleID) { styleOptions }
                                .frame(width: 200)
                        }
                    }
                    HStack {
                        Button("Cancel") { isAddingAppStyle = false }
                        Spacer()
                        MurmurButton("Save App Style", style: .primary) {
                            guard let app = applications.first(where: { $0.id == selectedAppID }) else { return }
                            if store.setAppRule(bundleID: app.bundleID, appName: app.name, styleID: selectedStyleID) {
                                selectedAppID = ""
                                isAddingAppStyle = false
                            }
                        }
                        .disabled(selectedAppID.isEmpty || store.isReadOnly)
                    }
                }
                .writingSurface()
            }
        }
    }

    private var memoryIntroduction: some View {
        HStack {
            Text("Background for smart cleanup")
                .font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
            Spacer()
            Toggle("Use memory", isOn: Binding(
                get: { store.memoryEnabled }, set: { store.setMemoryEnabled($0) }
            ))
            .toggleStyle(.switch)
            .font(DS.Font.body)
            .disabled(store.isReadOnly)
        }
    }

    private var memoryEditor: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            TextField("For example: I run a design studio and prefer British spelling.", text: $memoryText, axis: .vertical)
                .lineLimit(10...16)
                .textFieldStyle(.plain)
                .font(DS.Font.bodyLarge)
                .foregroundStyle(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                .accessibilityLabel("Background for smart cleanup")
                .focused($isMemoryEditorFocused)
                .task(id: memoryText) {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    persistMemory()
                }
            Divider().overlay(DS.Color.borderSubtle)
            HStack(spacing: DS.Space.base) {
                appPicker("Applies to", selection: $memoryAppID, includesAllApps: true)
                    .onChange(of: memoryAppID) { _, _ in persistMemory() }
                Spacer(minLength: 0)
                Text(memoryText.count > PersonalizationStore.maximumMemoryLength
                     ? "Too long · \(memoryText.count)/\(PersonalizationStore.maximumMemoryLength)"
                     : editingMemoryID != nil && memoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "Use Delete to remove this note"
                     : "Changes save automatically")
                    .font(DS.Font.caption)
                    .foregroundStyle(memoryText.count > PersonalizationStore.maximumMemoryLength
                                     ? DS.Color.warningAmber : DS.Color.textSecondary)
                if let current = store.memories.first(where: { $0.id == editingMemoryID }),
                   !current.isEnabled {
                    PersonalizationActionButton("Enable note") {
                        store.setMemoryEnabled(current.id, enabled: true)
                    }
                }
                if editingMemoryID != nil {
                    PersonalizationActionButton("New note") {
                        persistMemory()
                        resetMemoryEditor()
                        isMemoryEditorFocused = true
                    }
                }
                if let id = editingMemoryID {
                    PersonalizationActionButton("Delete note", icon: .trash2) {
                        if store.deleteMemory(id) { resetMemoryEditor() }
                    }
                }
            }
        }
        .writingSurface()
        .disabled(store.isReadOnly)
    }


    private var savedMemories: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            let otherNotes = store.memories.filter { $0.id != editingMemoryID }
            if !otherNotes.isEmpty {
                Text("Other notes")
                    .font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
                ForEach(otherNotes) { memory in
                    HStack(spacing: DS.Space.base) {
                        Button {
                            persistMemory()
                            loadMemory(memory, focus: true)
                        } label: {
                            VStack(alignment: .leading, spacing: DS.Space.tight) {
                                Text(memory.text)
                                    .font(DS.Font.body).foregroundStyle(DS.Color.textPrimary)
                                    .lineLimit(2)
                                Text(scopeName(bundleID: memory.bundleID, name: memory.appName))
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Toggle("Use note", isOn: Binding(
                            get: { memory.isEnabled },
                            set: { store.setMemoryEnabled(memory.id, enabled: $0) }
                        ))
                        .labelsHidden()
                        .accessibilityLabel("Use note: \(memory.text)")
                    }
                    .padding(DS.Space.base)
                    .background(DS.Color.card, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                }
            }
        }
    }

    private var styleOptions: some View {
        ForEach(WritingStyle.builtIns) { Text($0.name).tag($0.id) }
    }

    private func appPicker(_ title: String, selection: Binding<String>, includesAllApps: Bool) -> some View {
        HStack(spacing: DS.Space.snug) {
            Picker(title, selection: selection) {
                Text(includesAllApps ? "All apps" : "Choose an app").tag("")
                ForEach(applications) { Text($0.name).tag($0.id) }
            }
            .frame(minWidth: 170, maxWidth: 260)
            .accessibilityLabel(title)
            Button("Browse…") {
                guard let app = PersonalizationApplications.choose() else { return }
                addApplication(app)
                selection.wrappedValue = app.id
            }
            .accessibilityLabel("Browse installed apps for \(title.lowercased())")
        }
    }

    private func appLabel(id: String, name: String) -> some View {
        HStack(spacing: DS.Space.snug) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            Text(name).font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textPrimary)
        }
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text(title).font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
            Text(detail).font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scopeName(bundleID: String?, name: String?) -> String {
        bundleID == nil ? "All apps" : (name ?? "Selected app")
    }

    private func addApplication(_ app: PersonalizationApplication) {
        applications.removeAll { $0.id == app.id }
        applications.append(app)
        applications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func loadMemory(_ memory: WritingMemory, focus: Bool) {
        editingMemoryID = memory.id
        memoryText = memory.text
        memoryAppID = memory.bundleID ?? ""
        isMemoryEditorFocused = focus
        if let id = memory.bundleID, !applications.contains(where: { $0.id == id }) {
            addApplication(PersonalizationApplication(bundleID: id, name: memory.appName ?? "Selected app", url: nil))
        }
    }

    private func resetMemoryEditor() {
        editingMemoryID = nil
        memoryText = ""
        memoryAppID = ""
    }

    private func persistMemory() {
        guard !store.isReadOnly else { return }
        let trimmed = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard memoryText.count <= PersonalizationStore.maximumMemoryLength else { return }
        guard !trimmed.isEmpty else { return }
        let app = applications.first { $0.id == memoryAppID }
        guard store.saveMemory(id: editingMemoryID, text: memoryText,
                               bundleID: memoryAppID.isEmpty ? nil : memoryAppID,
                               appName: app?.name, quietly: true) else { return }
        if editingMemoryID == nil { editingMemoryID = store.memories.first?.id }
    }
}

private extension View {
    func writingSurface() -> some View {
        padding(DS.Space.roomy)
            .background(DS.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    }
}
