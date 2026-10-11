import SwiftUI

/// Saves history edits without reinserting text; Smart Learning extracts only
/// reusable spelling changes according to the Dictionary preference.
struct DictationCorrectionSheet: View {
    let run: DictationRun
    @Environment(\.dismiss) private var dismiss
    @State private var correctedText: String
    @State private var showProcessingDetails: Bool
    @State private var saveError: String?
    @State private var savedText: String
    @State private var historySavedDuringReview = false

    init(run: DictationRun) {
        self.run = run
        _correctedText = State(initialValue: run.text)
        _savedText = State(initialValue: run.text)
        _showProcessingDetails = State(initialValue: run.fallbackReason != nil)
    }

    private var originalOutput: String { run.deliveredText ?? run.text }
    private var trimmedText: String { correctedText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasTextChange: Bool { trimmedText != savedText }
    private var appName: String {
        run.bundleID.map { PersonalizationApplications.name(for: $0) } ?? "App not recorded"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text("Review dictation").font(DS.Font.pageTitle).foregroundStyle(DS.Color.textPrimary)
                Text("Edit your saved transcript. Changes here don't replace text already inserted in another app.")
                    .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.wide)

            Divider().overlay(DS.Color.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.wide) {
                    originals
                    editor
                    Text("Smart Learning reviews spelling edits using your Dictionary preference. Suggestions appear in Personalization → Dictionary.")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    processingDetails
                    if let saveError {
                        HStack(alignment: .top, spacing: DS.Space.snug) {
                            LucideIcon(.circleAlert, size: 17).foregroundStyle(DS.Color.warningAmber)
                            Text(saveError).font(DS.Font.body).foregroundStyle(DS.Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(DS.Space.base).background(DS.Color.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                    }
                }
                .padding(DS.Space.wide)
            }

            Divider().overlay(DS.Color.borderSubtle)
            HStack {
                Spacer()
                Button(historySavedDuringReview && !hasTextChange ? "Close" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                MurmurButton("Save Changes", style: .primary) { save() }
                    .disabled(trimmedText.isEmpty || !hasTextChange)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Space.wide)
        }
        .frame(width: 760, height: 730)
        .background(DS.Color.canvas)
    }

    private var originals: some View {
        HStack(alignment: .top, spacing: DS.Space.base) {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Text("Original recognition").font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textPrimary)
                if let raw = run.rawText {
                    readOnlyText(raw)
                } else {
                    Text("The original recognition wasn't saved for this older dictation.")
                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Text("Original output").font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textPrimary)
                readOnlyText(originalOutput)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func readOnlyText(_ text: String) -> some View {
        ScrollView {
            Text(text).font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.base)
        }
        .frame(height: 116)
        .background(DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack {
                Text("Saved transcript").font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textPrimary)
                Spacer()
                if correctedText != originalOutput {
                    Button("Restore Original Output") {
                        correctedText = originalOutput
                        saveError = nil
                    }
                    .font(DS.Font.caption)
                }
            }
            TextEditor(text: $correctedText)
                .font(DS.Font.bodyLarge).foregroundStyle(DS.Color.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(DS.Space.snug).frame(minHeight: 120)
                .background(DS.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
                    .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline))
                .accessibilityLabel("Edit saved transcript")
        }
    }

    private var processingDetails: some View {
        DisclosureGroup("Processing details", isExpanded: $showProcessingDetails) {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                detail("Recorded", value: run.date.formatted(date: .abbreviated, time: .shortened))
                detail("Destination", value: appName)
                detail("Speech model", value: run.engine)
                detail("Writing style", value: run.styleID.flatMap(WritingStyle.find)?.name ?? "Not recorded")
                detail("Cleanup", value: run.cleanupEngine ?? "Not recorded")
                if let seconds = run.cleanupSeconds { detail("Cleanup time", value: String(format: "%.2f seconds", seconds)) }
                detail("Total processing", value: String(format: "%.2f seconds", run.processSeconds))
                if let reason = run.fallbackReason {
                    VStack(alignment: .leading, spacing: DS.Space.tight) {
                        Text("Fallback used").font(DS.Font.bodyEmphasis)
                        Text(reason).font(DS.Font.body).textSelection(.enabled)
                    }
                    .foregroundStyle(DS.Color.textPrimary)
                    .padding(.top, DS.Space.snug)
                }
                if let corrections = run.corrections, !corrections.isEmpty {
                    Text("Applied dictionary rules").font(DS.Font.bodyEmphasis)
                        .foregroundStyle(DS.Color.textPrimary).padding(.top, DS.Space.snug)
                    ForEach(Array(corrections.enumerated()), id: \.offset) { _, correction in
                        Text("\(correction.from) → \(correction.to) (\(correction.count))")
                            .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary).textSelection(.enabled)
                    }
                }
            }
            .padding(.top, DS.Space.base)
        }
        .font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textPrimary)
    }

    private func detail(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.base) {
            Text(label).foregroundStyle(DS.Color.textSecondary).frame(width: 136, alignment: .leading)
            Text(value).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(DS.Font.body)
    }

    private func save() {
        saveError = nil
        if hasTextChange {
            guard RunLog.correct(id: run.id, text: trimmedText) else {
                saveError = "The transcript couldn't be saved. It may have been deleted, or the history file may be unavailable. Your edits remain here so you can copy them."
                return
            }
            savedText = trimmedText
            historySavedDuringReview = true
        }
        let before = run.text, after = trimmedText, scope = run.bundleID
        Task { _ = await LearnedTermStore.shared.learn(before: before, after: after, bundleID: scope) }
        dismiss()
    }
}
