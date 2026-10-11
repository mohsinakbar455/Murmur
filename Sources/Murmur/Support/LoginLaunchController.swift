import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
final class LoginLaunchController {
    static let shared = LoginLaunchController()
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var errorMessage: String?
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            isEnabled = SMAppService.mainApp.status == .enabled
            errorMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow Murmur in System Settings → General → Login Items." : nil
        } catch { errorMessage = error.localizedDescription }
    }
}
