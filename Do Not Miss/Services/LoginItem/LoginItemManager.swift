import Foundation
import Combine
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var currentStatus: SMAppService.Status?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isUpdating: Bool = false

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        guard let currentStatus else {
            return false
        }

        switch currentStatus {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    var statusDescription: String {
        guard let currentStatus else {
            return L10n.tr("login_item.status.checking")
        }

        switch currentStatus {
        case .enabled:
            return L10n.tr("status.active")
        case .notRegistered:
            return L10n.tr("status.inactive")
        case .requiresApproval:
            return L10n.tr("login_item.status.requires_approval")
        case .notFound:
            return L10n.tr("login_item.status.unavailable_not_found")
        @unknown default:
            return L10n.tr("login_item.status.unknown")
        }
    }

    func refreshStatus() {
        currentStatus = service.status
    }

    func setLaunchAtLogin(enabled: Bool) async throws {
        isUpdating = true
        defer {
            isUpdating = false
            refreshStatus()
        }

        lastErrorMessage = nil

        do {
            if enabled {
                try service.register()
            } else {
                try await service.unregister()
            }
        } catch {
            if isBenignError(error, enabling: enabled) {
                return
            }

            lastErrorMessage = userFacingErrorMessage(for: error, enabling: enabled)
            throw error
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func openLoginItemsSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func isBenignError(_ error: Error, enabling: Bool) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SMAppServiceErrorDomain else {
            return false
        }

        if enabling {
            return nsError.code == Int(kSMErrorAlreadyRegistered)
        }

        return nsError.code == Int(kSMErrorJobNotFound)
    }

    private func userFacingErrorMessage(for error: Error, enabling: Bool) -> String {
        let nsError = error as NSError

        if nsError.domain == SMAppServiceErrorDomain,
           nsError.code == Int(kSMErrorLaunchDeniedByUser) {
            return L10n.tr("login_item.error.launch_denied")
        }

        let action = enabling ? L10n.tr("common.enable") : L10n.tr("common.disable")
        return L10n.tr("login_item.error.could_not_toggle", action, error.localizedDescription)
    }
}
