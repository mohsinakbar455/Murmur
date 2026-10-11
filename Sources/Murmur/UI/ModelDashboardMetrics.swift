import Foundation

struct ModelCatalogSummary<Model: Identifiable> {
    let additionalModels: [Model]
    let all: Int
    let installed: Int
    var available: Int { all - installed }

    init(models: [Model], activeModelID: Model.ID?, isInstalled: (Model) -> Bool) {
        additionalModels = models.filter { $0.id != activeModelID }
        all = models.count
        installed = models.filter(isInstalled).count
    }
}

enum DashboardMetrics {
    static func spokenAudio(_ seconds: Double) -> String {
        String(format: "%.1f min", seconds / 60)
    }
}
