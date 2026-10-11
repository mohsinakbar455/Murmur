import SwiftUI

struct WritingAssistantBadge: View {
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            LucideIcon(.sparkleFilled, size: 13)
                .foregroundStyle(DS.Color.accent)
                .frame(width: 26, height: 26)
                .background {
                    if reduceTransparency { Circle().fill(DS.Color.cardElevated) }
                    else { Color.clear.glassEffect(.clear.interactive(), in: .circle) }
                }
                .scaleEffect(hover && !reduceMotion ? 1.06 : 1)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hover)

        .help("Writing Assistant")
        .accessibilityLabel("Open Writing Assistant")
        .accessibilityValue(selected ? "Text selected" : "No text selected")
    }
}

struct WritingAssistantView: View {
    @Bindable var controller: WritingAssistantController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var instructionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: controller.modelReady ? 10 : 6) {
            HStack {
                Text("Writing Assistant").font(DS.Font.bodyEmphasis)
                Spacer()
                Button { controller.close() } label: { LucideIcon(.x, size: 15).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).help("Close").accessibilityLabel("Close Writing Assistant")
            }
            if controller.modelReady {
                instructionField
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if controller.hasResult { result }
                        else {
                            if controller.selectionUnavailable {
                                Text("No selection captured").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            } else if !controller.hasTarget { sourceEditor }
                            else {
                                Text(controller.selectedCount > 0 ? "\(controller.selectedCount) words selected · \(controller.appName)" : "Select text to edit, or describe what to compose.")
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            }
                            if controller.canUndoLastEdit {
                                Button("Undo last edit") { controller.undoLastEdit() }
                                    .buttonStyle(.plain).font(DS.Font.caption).foregroundStyle(DS.Color.accent)
                                    .disabled(controller.busy || controller.listening)
                            }
                            HStack(spacing: 8) {
                                primaryAction(.proofread, icon: .fileSearch)
                                primaryAction(.rewrite, icon: .pencil)
                            }
                            Divider()
                            VStack(spacing: 1) {
                                action(.friendly, icon: .smile)
                                action(.professional, icon: .briefcase)
                                action(.concise, icon: .alignLeft)
                            }
                            Divider()
                            VStack(spacing: 1) {
                                action(.summary, icon: .fileText)
                                action(.keyPoints, icon: .listChecks)
                                action(.list, icon: .list)
                                action(.table, icon: .table)
                            }
                            Divider()
                            action(.compose, icon: .pencil)
                        }
                    }
                }
                if !controller.status.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        if controller.busy { ProgressView().controlSize(.small) }
                        Text(controller.status).font(DS.Font.caption).fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(controller.status)
                    }
                    .foregroundStyle(DS.Color.textSecondary)
                }
                if controller.busy { Button("Cancel") { controller.close() }.buttonStyle(.plain).foregroundStyle(DS.Color.accent) }
            } else {
                Button { controller.openModels() } label: {
                    HStack(spacing: 8) {
                        LucideIcon(.download, size: 16)
                        Text("Download a Qwen model to start")
                            .font(DS.Font.bodyEmphasis)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        LucideIcon(.chevronRight, size: 14)
                    }
                    .foregroundStyle(DS.Color.actionRequired)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(DS.Color.actionRequired.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Choose and download a local Qwen writing model")
                .accessibilityLabel("Download a Qwen model to use Writing Assistant")
            }
        }
        .padding(controller.modelReady ? 14 : 12)
        .frame(width: 328, height: controller.modelReady ? 480 : 92, alignment: .top)
        .foregroundStyle(DS.Color.textPrimary)
        .background {
            if reduceTransparency { RoundedRectangle(cornerRadius: 20).fill(DS.Color.cardElevated) }
            else { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 20)) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .tint(DS.Color.accent)
        .preferredColorScheme(Settings.shared.appearanceMode.colorScheme)
        .onChange(of: controller.composeMode) { _, value in if value { instructionFocused = true } }
    }

    private var instructionField: some View {
        HStack(spacing: 8) {
            LucideIcon(.sparkles, size: 16).foregroundStyle(DS.Color.accent)
            TextField(controller.composeMode ? "Describe what to compose…" : "Describe your change…", text: $controller.instruction)
                .textFieldStyle(.plain).font(DS.Font.body)
                .focused($instructionFocused)
                .onSubmit { controller.run(.custom) }
                .disabled(controller.busy || controller.listening || controller.hasResult)
                .accessibilityLabel("Custom writing instruction")
            Button { controller.toggleMicrophone() } label: {
                LucideIcon(controller.listening ? .stop : .mic, size: 16).frame(width: 24, height: 28)
            }
            .buttonStyle(.plain).disabled(controller.busy || controller.hasResult)
            .foregroundStyle(controller.listening ? DS.Color.accent : DS.Color.textSecondary)
            .help(controller.listening ? "Finish instruction" : "Dictate an instruction")
            .accessibilityLabel(controller.listening ? "Finish recording instruction" : "Dictate an instruction")
            if !controller.instruction.isEmpty && !controller.hasResult {
                Button { controller.run(.custom) } label: { LucideIcon(.arrowRight, size: 16).frame(width: 24, height: 28) }
                    .buttonStyle(.plain).disabled(!controller.canGenerate).accessibilityLabel("Apply instruction")
            }
        }
        .padding(.horizontal, 12).frame(height: 42)
        .background(DS.Color.cardElevated.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Text to edit").font(DS.Font.caption)
                Spacer()
                Button("Paste text") { controller.paste() }.buttonStyle(.plain).foregroundStyle(DS.Color.accent)
            }
            TextEditor(text: $controller.source)
                .font(DS.Font.body).scrollContentBackground(.hidden)
                .frame(height: 80).padding(6)
                .background(DS.Color.card, in: RoundedRectangle(cornerRadius: 8))
                .disabled(controller.busy || controller.listening)
                .accessibilityLabel("Text to edit")
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(controller.output).font(DS.Font.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(DS.Color.card, in: RoundedRectangle(cornerRadius: 10))
            if controller.needsReview {
                Button("Replace selected text") { controller.applyReviewedResult() }
                    .buttonStyle(.borderedProminent).disabled(controller.busy)
            }
            HStack {
                Button("Copy result") { controller.copy() }
                Spacer()
                if controller.receipt != nil { Button("Undo") { controller.undo() }.disabled(controller.busy) }
                Button("Done") { controller.close() }
            }.font(DS.Font.body).foregroundStyle(DS.Color.accent).buttonStyle(.plain)
            if !controller.source.isEmpty {
                Button("Copy original") { controller.copy(original: true) }
                    .buttonStyle(.plain).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    private func primaryAction(_ value: WritingAction, icon: LucideIcon.Name) -> some View {
        Button { controller.run(value) } label: {
            VStack(spacing: 6) { LucideIcon(icon, size: 20); Text(value.title).font(DS.Font.bodyEmphasis) }
                .frame(maxWidth: .infinity).frame(height: 58)
                .background(DS.Color.cardElevated.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(!controller.canGenerate || controller.source.isEmpty)
    }

    private func action(_ value: WritingAction, icon: LucideIcon.Name) -> some View {
        Button { controller.run(value) } label: {
            HStack(spacing: 10) {
                LucideIcon(icon, size: 16).frame(width: 20)
                Text(value.title).font(DS.Font.body)
                Spacer()
            }.padding(.horizontal, 8).frame(height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!controller.canGenerate || (value != .compose && controller.source.isEmpty))
            .help(value == .table ? "Create a plain-text Markdown table" : value.title)
    }
}
