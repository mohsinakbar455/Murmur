import Testing
@testable import Murmur

@Suite("Model counts and dashboard metrics")
struct ModelDashboardMetricsTests {
    private struct Model: Identifiable {
        let id: Int
        let installed: Bool
    }

    @Test("Active model is included in installed and total counts")
    func activeModelCounts() {
        let models = [Model(id: 1, installed: false), Model(id: 2, installed: true), Model(id: 3, installed: false)]
        let summary = ModelCatalogSummary(models: models, activeModelID: 2) { $0.installed }
        #expect(summary.additionalModels.map(\.id) == [1, 3])
        #expect(summary.all == 3)
        #expect(summary.installed == 1)
        #expect(summary.available == 2)
    }

    @Test("Spoken audio is displayed in minutes")
    func spokenAudioMinutes() {
        #expect(DashboardMetrics.spokenAudio(1_252) == "20.9 min")
        #expect(DashboardMetrics.spokenAudio(30) == "0.5 min")
        #expect(DashboardMetrics.spokenAudio(0) == "0.0 min")
    }
}
