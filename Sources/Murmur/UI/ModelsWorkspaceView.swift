import SwiftUI

struct ModelsWorkspaceView: View {
    @State private var writing = false
    var body: some View {
        Group {
            if writing {
                WritingModelsView(writing: $writing)
            } else {
                VoiceModelsView(writing: $writing)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNavigate)) { notification in
            if let value = notification.object as? String, value == "writing-models" { writing = true }
        }
    }
}

struct ModelPurposePicker: View {
    @Binding var writing: Bool

    var body: some View {
        Picker("Model purpose", selection: $writing) {
            Text("Speech recognition").tag(false)
            Text("Writing & cleanup").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, DS.Space.tight)
    }
}

struct ModelCatalogHeading: View {
    @Binding var filter: ModelCatalogFilter
    let allCount: Int
    let installedCount: Int
    let availableCount: Int
    let filterLabel: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.roomy) {
                heading
                Spacer(minLength: DS.Space.snug)
                ModelFilterControl(
                    selection: $filter,
                    allCount: allCount,
                    installedCount: installedCount,
                    availableCount: availableCount,
                    accessibilityLabel: filterLabel
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DS.Space.snug) {
                heading
                HStack {
                    Spacer()
                    ModelFilterControl(
                        selection: $filter,
                        allCount: allCount,
                        installedCount: installedCount,
                        availableCount: availableCount,
                        accessibilityLabel: filterLabel
                    )
                }
            }
        }
    }

    private var heading: some View {
        Text("Models")
            .font(DS.Font.sectionTitle)
            .foregroundStyle(DS.Color.textPrimary)
            .fixedSize(horizontal: true, vertical: false)
    }
}
