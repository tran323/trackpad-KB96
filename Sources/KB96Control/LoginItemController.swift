import Combine
import Foundation
import ServiceManagement

final class LoginItemController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var status = ""

    private let configuredKey = "launchAtLoginConfigured"

    func configureOnFirstLaunch() {
        refresh()
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        // Preserve an existing registration, including one disabled in System Settings.
        if enabled {
            UserDefaults.standard.set(true, forKey: configuredKey)
        } else {
            setEnabled(true)
        }
    }

    func refresh() {
        let serviceStatus = SMAppService.mainApp.status
        enabled = serviceStatus == .enabled || serviceStatus == .requiresApproval
        requiresApproval = serviceStatus == .requiresApproval
        switch serviceStatus {
        case .enabled:
            status = "KB96 Control will open automatically when you sign in."
        case .requiresApproval:
            status = "Allow KB96 Control in System Settings → General → Login Items."
        case .notRegistered:
            status = "Launch at login is off."
        case .notFound:
            status = "Move KB96 Control.app to Applications and open it there to enable launch at login."
        @unknown default:
            status = "Could not determine the login item status."
        }
    }

    func setEnabled(_ value: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            status = "Open the bundled KB96 Control.app from Applications to change launch at login."
            return
        }
        do {
            let service = SMAppService.mainApp
            if value {
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            UserDefaults.standard.set(true, forKey: configuredKey)
            refresh()
        } catch {
            refresh()
            status = "Could not change launch at login: \(error.localizedDescription)"
        }
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
