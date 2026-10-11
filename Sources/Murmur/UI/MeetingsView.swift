import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MeetingsView: View {
    @State private var controller = MeetingController.shared
    @State private var selectedID: UUID?
    @State private var query = ""
    @State private var tab = "Transcript"
    @State private var showStart = false
    @State private var deleteTarget: MeetingRecord?
    @State private var exportError: String?
    @State private var highlightedSegmentID: UUID?

    private var visibleMeetings: [MeetingRecord] { controller.store.meetings.filter { $0.matches(query.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    private var current: MeetingRecord? {
        if let selectedID, let selected = visibleMeetings.first(where: { $0.id == selectedID }) { return selected }
        if let active = controller.activeMeetingID,
           let recording = visibleMeetings.first(where: { $0.id == active }) { return recording }
        return visibleMeetings.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            PageHeader(title: "Meetings", subtitle: "Local transcripts, useful notes, and the moments behind them.") {
                if controller.isBusy {
                    MeetingStatusView()
                } else {
                    Button { showStart = true } label: { Label("New Meeting", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(DS.Color.accent).foregroundStyle(DS.Color.textOnAccent)
                }
            }
            if let message = controller.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(DS.Color.warningAmber)
                    Text(message).font(DS.Font.body).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { controller.dismissError() }
                }.padding(14).background(DS.Color.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(controller.store.loadWarnings.prefix(3), id: \.self) { warning in
                Text(warning).font(DS.Font.caption).foregroundStyle(DS.Color.warningAmber).textSelection(.enabled)
            }
            if controller.store.meetings.isEmpty { emptyState }
            else {
                meetingToolbar
                if visibleMeetings.count > 1 {
                    meetingPicker
                }
                meetingDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.panel)
        .background(DS.Color.canvas)
        .sheet(isPresented: $showStart) { MeetingStartSheet(controller: controller) }
        .onChange(of: controller.activeMeetingID) { _, id in if let id { selectedID = id; tab = "Transcript" } }
        .confirmationDialog("Delete this meeting?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete meeting and notes", role: .destructive) {
                if let target = deleteTarget { controller.delete(target.id); if selectedID == target.id { selectedID = nil } }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { Text("The transcript and notes will be permanently removed from this Mac.") }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var meetingToolbar: some View {
        MurmurCard(padding: DS.Space.base) {
            HStack(spacing: DS.Space.roomy) {
                HStack(spacing: DS.Space.snug) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DS.Color.textSecondary)
                    TextField("Search meetings", text: $query)
                        .textFieldStyle(.plain)
                        .font(DS.Font.body)
                        .accessibilityLabel("Search meetings")
                }
                .padding(.horizontal, DS.Space.snug)
                .frame(height: 32)
                .background(DS.Color.cardElevated, in: RoundedRectangle(cornerRadius: DS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Color.borderSubtle))
                .frame(maxWidth: 320)

                Spacer(minLength: 0)
                Text("\(visibleMeetings.count) \(visibleMeetings.count == 1 ? "meeting" : "meetings")")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Divider().frame(height: 24)
                Label("On-device", systemImage: "shield")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.base) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 24))
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 56, height: 56)
                .background(DS.Color.cardElevated, in: Circle())
            Text("Keep the conversation")
                .font(DS.Font.cardTitleLarge)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Capture your microphone and, if you choose, audio from a call. Transcripts stay on this Mac; audio recordings are not retained.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Start your first meeting") { showStart = true }
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.accent)
                .buttonStyle(.plain)
                .disabled(controller.isBusy)
                .padding(.top, DS.Space.tight)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(DS.Color.card, in: RoundedRectangle(cornerRadius: DS.Radius.cardLarge))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
            .strokeBorder(DS.Color.borderSubtle, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    private var meetingPicker: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Text("Saved meetings")
                .font(DS.Font.cardTitle)
                .foregroundStyle(DS.Color.textPrimary)
            ScrollView(.horizontal) {
                LazyHStack(spacing: DS.Space.snug) {
                    ForEach(visibleMeetings) { meeting in
                        Button {
                            selectedID = meeting.id
                            tab = "Transcript"
                            highlightedSegmentID = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(meeting.title).font(DS.Font.bodyEmphasis).lineLimit(2)
                                    Spacer(minLength: 0)
                                    if meeting.id == controller.activeMeetingID {
                                        Circle().fill(DS.Color.recordRed).frame(width: 7, height: 7)
                                    }
                                }
                                Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                                Text("\(meeting.segments.count) segments\(meeting.interrupted ? " · Interrupted" : "")")
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                            }
                            .foregroundStyle(DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.base)
                            .background(current?.id == meeting.id ? DS.Color.cardSelected : DS.Color.card,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.card))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card)
                                .strokeBorder(current?.id == meeting.id ? DS.Color.accent.opacity(0.65) : DS.Color.borderSubtle))
                        }
                        .frame(width: 230)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(current?.id == meeting.id ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var meetingDetail: some View {
        if let meeting = current {
            detail(meeting)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detail(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            MurmurCard(padding: DS.Space.roomy) {
                VStack(alignment: .leading, spacing: DS.Space.base) {
                    TextField("Meeting title", text: Binding(
                        get: { controller.store.meeting(meeting.id)?.title ?? "" },
                        set: { controller.updateDetails(id: meeting.id, title: $0) }
                    ))
                    .font(DS.Font.sectionTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                    .textFieldStyle(.plain)

                    Text("\(meeting.source) · \(meeting.modelID) · On this Mac")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    if meeting.interrupted {
                        Label("Recording was interrupted. The saved transcript remains available.", systemImage: "exclamationmark.circle")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.warningAmber)
                    }

                    Rectangle().fill(DS.Color.borderSubtle).frame(height: 1)

                    HStack(spacing: DS.Space.snug) {
                        Picker("Meeting section", selection: $tab) {
                            Text("Transcript").tag("Transcript")
                            Text("Draft notes").tag("Draft notes")
                            Text("Your notes").tag("Your notes")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                        Spacer(minLength: 0)
                        Menu {
                            ForEach(MeetingExport.allCases) { format in
                                Button(format.rawValue) { export(meeting, as: format) }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(DS.Color.textSecondary)
                                .frame(width: 30, height: 28)
                                .background(DS.Color.cardElevated, in: RoundedRectangle(cornerRadius: DS.Radius.control))
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Color.borderSubtle))
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel("Export meeting")
                        .help("Export meeting")
                        Button { deleteTarget = meeting } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(DS.Color.textSecondary)
                                .frame(width: 30, height: 28)
                                .background(DS.Color.cardElevated, in: RoundedRectangle(cornerRadius: DS.Radius.control))
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Color.borderSubtle))
                        }
                        .buttonStyle(.plain)
                        .disabled(meeting.id == controller.activeMeetingID || controller.summarizingIDs.contains(meeting.id))
                        .accessibilityLabel("Delete meeting")
                        .help("Delete meeting")
                    }
                }
            }
            switch tab {
            case "Your notes":
                TextEditor(text: Binding(get: { controller.store.meeting(meeting.id)?.notes ?? "" }, set: { controller.updateDetails(id: meeting.id, notes: $0) }))
                    .font(DS.Font.body)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Space.base)
                    .background(DS.Color.card, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Color.borderSubtle))
            case "Draft notes": summary(meeting)
            default: transcript(meeting)
            }
        }
    }

    private func transcript(_ meeting: MeetingRecord) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Transcript")
                            .font(DS.Font.cardTitle)
                            .foregroundStyle(DS.Color.textPrimary)
                        Spacer()
                        Text("\(meeting.segments.count) segments")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .padding(.horizontal, DS.Space.card)
                    .padding(.vertical, DS.Space.roomy)
                    Rectangle().fill(DS.Color.borderSubtle).frame(height: 1)

                    if meeting.segments.isEmpty {
                        Text(controller.isRecording ? "Listening… Transcribed lines appear after a pause. Use headphones to reduce echo between channels." : "No speech was transcribed.")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.textSecondary)
                            .padding(DS.Space.card)
                    }
                    ForEach(meeting.orderedSegments) { segment in
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: DS.Space.roomy) {
                                Text(MeetingExport.clock(segment.start))
                                    .font(DS.Font.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Color.textTertiary)
                                    .frame(width: 70, alignment: .leading)
                                VStack(alignment: .leading, spacing: DS.Space.snug) {
                                    HStack {
                                        Text(segment.speaker.rawValue)
                                            .font(DS.Font.label)
                                            .foregroundStyle(segment.speaker == .you ? DS.Color.accent : DS.Color.infoBlue)
                                        Spacer()
                                        if segment.issue != nil, controller.hasRetryAudio(for: segment.id) {
                                            Button(controller.retryingIDs.contains(segment.id) ? "Retrying…" : "Retry segment") {
                                                Task { await controller.retry(segmentID: segment.id) }
                                            }
                                            .disabled(controller.isBusy || controller.retryingIDs.contains(segment.id))
                                        }
                                    }
                                    Text(segment.issue.map { "Transcription unavailable: \($0)" } ?? segment.text)
                                        .font(DS.Font.transcriptText)
                                        .foregroundStyle(segment.issue == nil ? DS.Color.textPrimary : DS.Color.warningAmber)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.card)
                            .background(highlightedSegmentID == segment.id ? DS.Color.accentSoft : Color.clear)
                            Rectangle().fill(DS.Color.borderSubtle).frame(height: 1)
                        }
                        .id(segment.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.card, in: RoundedRectangle(cornerRadius: DS.Radius.cardLarge))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.cardLarge).strokeBorder(DS.Color.borderSubtle))
            }
            .onChange(of: highlightedSegmentID) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
            .onAppear { if let highlightedSegmentID { proxy.scrollTo(highlightedSegmentID, anchor: .center) } }
        }
    }

    private func summary(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Provisional draft. Citations are checked, but meaning and responsibility still need your review. Verify decisions and action owners against the transcript.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                Spacer()
                if controller.summarizingIDs.contains(meeting.id) { ProgressView().controlSize(.small) }
                Button(meeting.draftSummary.isEmpty ? "Generate notes" : "Regenerate") { Task { await controller.generateNotes(for: meeting.id) } }
                    .disabled(controller.isBusy || controller.summarizingIDs.contains(meeting.id) || !meeting.segments.contains(where: { !$0.text.isEmpty }))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if meeting.draftSummary.isEmpty {
                        Text("After recording, generate a draft of the main points, decisions and actions. Your transcript stays available if a writing model needs setup.")
                            .foregroundStyle(DS.Color.textSecondary).padding(.top, 20)
                    }
                    if !meeting.actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Action checklist").font(.headline)
                            ForEach(meeting.actionItems) { action in
                                Toggle(isOn: Binding(get: { action.isDone }, set: { controller.setActionDone(meetingID: meeting.id, actionID: action.id, done: $0) })) {
                                    Text(action.text).font(DS.Font.body).strikethrough(action.isDone).textSelection(.enabled)
                                }.toggleStyle(.checkbox)
                            }
                        }.padding(14).background(DS.Color.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(Array(meeting.draftSummary.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(line).font(line.hasPrefix("#") ? .headline : DS.Font.body).textSelection(.enabled)
                            let sources = meeting.orderedSegments.filter { line.contains(MeetingExport.clock($0.start)) }
                            if !sources.isEmpty {
                                HStack {
                                    ForEach(Array(sources.prefix(4))) { segment in
                                        Button { highlightedSegmentID = segment.id; tab = "Transcript" } label: {
                                            Label(MeetingExport.clock(segment.start), systemImage: "text.quote")
                                        }.font(DS.Font.caption).buttonStyle(.bordered).help("View source transcript")
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func export(_ meeting: MeetingRecord, as format: MeetingExport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        let safeTitle = meeting.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = String(safeTitle.prefix(100)) + "." + format.fileExtension
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try format.data(for: meeting).write(to: destination, options: .atomic) }
        catch { exportError = error.localizedDescription }
    }
}

private struct MeetingStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    let controller: MeetingController
    @State private var title = ""
    @State private var capture = "microphone"
    @State private var appID = ""
    private var apps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    private var source: MeetingCaptureSource {
        if capture == "system" { return .microphoneAndSystem }
        if capture == "app" { return .microphoneAndApp(bundleID: appID, name: apps.first(where: { $0.bundleIdentifier == appID })?.localizedName ?? appID) }
        return .microphone
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New meeting").font(DS.Font.pageTitle)
            Text("Choose exactly what Murmur can hear. Let participants know before recording.").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
            TextField("Meeting title (optional)", text: $title).textFieldStyle(.roundedBorder)
            Picker("Capture", selection: $capture) {
                Text("Microphone only").tag("microphone")
                Text("Microphone + one app").tag("app")
                Text("Microphone + all Mac audio").tag("system")
            }
            if capture == "app" {
                Picker("App audio", selection: $appID) {
                    Text("Choose an app").tag("")
                    ForEach(apps, id: \.processIdentifier) { app in Text(app.localizedName ?? app.bundleIdentifier!).tag(app.bundleIdentifier!) }
                }
                Text("For a browser, this includes audio from its other tabs. If the selected app cannot be captured, recording will not start.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            if capture == "system" {
                Label("All audio played by this Mac may be transcribed, including other apps and notifications.", systemImage: "speaker.wave.2")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.warningAmber)
            }
            Text("Speech: \(VoiceModelManager.shared.models.first(where: { $0.id == Settings.shared.selectedModelID })?.name ?? Settings.shared.selectedModelID)\nMicrophone: your current Settings selection\nYou and Remote label audio channels; remote people are not individually identified.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            Text("Processing stays on this Mac. Audio recordings are not retained. Transcripts and notes are kept until you delete the meeting.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start recording") {
                    let selectedSource = source
                    dismiss()
                    Task { await controller.start(source: selectedSource, title: title) }
                }
                .buttonStyle(.borderedProminent).tint(DS.Color.accent).foregroundStyle(DS.Color.textOnAccent)
                .disabled(capture == "app" && appID.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 510).background(DS.Color.canvas)
    }
}
