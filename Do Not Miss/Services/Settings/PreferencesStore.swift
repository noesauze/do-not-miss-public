import Foundation

enum WeeklyReviewWeekday: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    static let fallback: WeeklyReviewWeekday = .friday

    var id: Int {
        rawValue
    }

    var localizedName: String {
        let symbols = Calendar.autoupdatingCurrent.weekdaySymbols
        let index = rawValue - 1
        guard symbols.indices.contains(index) else {
            return "Friday"
        }
        return symbols[index]
    }
}

final class PreferencesStore {
    private enum Keys {
        static let weeklyReviewEnabled = "weeklyReview.enabled"
        static let weeklyReviewWeekday = "weeklyReview.weekday"
        static let weeklyReviewHour = "weeklyReview.hour"
        static let weeklyReviewMinute = "weeklyReview.minute"
        static let weeklyReviewLastAutomaticRunDate = "weeklyReview.lastAutomaticRunDate"
        static let weeklyReviewLastTriggeredSlotDate = "weeklyReview.lastTriggeredSlotDate"
    }

    private let defaults: UserDefaults

    private let defaultWeeklyReviewHour = 17
    private let defaultWeeklyReviewMinute = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var weeklyReviewEnabled: Bool {
        get { defaults.bool(forKey: Keys.weeklyReviewEnabled) }
        set { defaults.set(newValue, forKey: Keys.weeklyReviewEnabled) }
    }

    var weeklyReviewWeekday: WeeklyReviewWeekday {
        get {
            let raw = defaults.integer(forKey: Keys.weeklyReviewWeekday)
            return WeeklyReviewWeekday(rawValue: raw) ?? .fallback
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.weeklyReviewWeekday)
        }
    }

    var weeklyReviewHour: Int {
        get {
            let value = defaults.integer(forKey: Keys.weeklyReviewHour)
            return clamp(value, min: 0, max: 23, fallback: defaultWeeklyReviewHour)
        }
        set {
            let value = clamp(newValue, min: 0, max: 23, fallback: defaultWeeklyReviewHour)
            defaults.set(value, forKey: Keys.weeklyReviewHour)
        }
    }

    var weeklyReviewMinute: Int {
        get {
            let value = defaults.integer(forKey: Keys.weeklyReviewMinute)
            return clamp(value, min: 0, max: 59, fallback: defaultWeeklyReviewMinute)
        }
        set {
            let value = clamp(newValue, min: 0, max: 59, fallback: defaultWeeklyReviewMinute)
            defaults.set(value, forKey: Keys.weeklyReviewMinute)
        }
    }

    var weeklyReviewLastAutomaticRunDate: Date? {
        get { defaults.object(forKey: Keys.weeklyReviewLastAutomaticRunDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.weeklyReviewLastAutomaticRunDate) }
    }

    var weeklyReviewLastTriggeredSlotDate: Date? {
        get { defaults.object(forKey: Keys.weeklyReviewLastTriggeredSlotDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.weeklyReviewLastTriggeredSlotDate) }
    }

    var weeklyReviewTimeComponents: DateComponents {
        DateComponents(hour: weeklyReviewHour, minute: weeklyReviewMinute)
    }

    var weeklyReviewTimeDate: Date {
        var components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
        components.hour = weeklyReviewHour
        components.minute = weeklyReviewMinute
        components.second = 0
        return Calendar.autoupdatingCurrent.date(from: components) ?? Date()
    }

    func setWeeklyReviewTime(from date: Date) {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        weeklyReviewHour = components.hour ?? defaultWeeklyReviewHour
        weeklyReviewMinute = components.minute ?? defaultWeeklyReviewMinute
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.weeklyReviewEnabled: true,
            Keys.weeklyReviewWeekday: WeeklyReviewWeekday.friday.rawValue,
            Keys.weeklyReviewHour: defaultWeeklyReviewHour,
            Keys.weeklyReviewMinute: defaultWeeklyReviewMinute
        ])
    }

    private func clamp(_ value: Int, min minValue: Int, max maxValue: Int, fallback: Int) -> Int {
        guard minValue <= value, value <= maxValue else {
            return fallback
        }
        return value
    }
}
