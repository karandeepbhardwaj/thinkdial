import Foundation
import ServiceManagement

enum LoginItemController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "ThinkDial opens when you log in."
        case .requiresApproval:
            return "macOS is waiting for approval in System Settings → General → Login Items."
        case .notRegistered:
            return "ThinkDial does not open at login."
        case .notFound:
            return "Launch at login needs the app to be installed as ThinkDial.app."
        @unknown default:
            return "Login item status is unavailable."
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
