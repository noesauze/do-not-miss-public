import Foundation

final class OnboardingStateStore {
    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasCompleted: Bool {
        userDefaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    func markCompleted() {
        userDefaults.set(true, forKey: Keys.hasCompletedOnboarding)
    }
}
