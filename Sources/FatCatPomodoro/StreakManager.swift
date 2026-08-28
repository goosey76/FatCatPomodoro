import Foundation

class StreakManager: ObservableObject {
    static let shared = StreakManager()

    @Published private(set) var currentStreak: Int
    @Published private(set) var longestStreak: Int
    private var lastCompletionDate: Date?

    private init() {
        currentStreak = UserDefaults.standard.integer(forKey: "streak.current")
        longestStreak = UserDefaults.standard.integer(forKey: "streak.longest")
        lastCompletionDate = UserDefaults.standard.object(forKey: "streak.lastCompletionDate") as? Date
    }

    func recordSession() {
        let calendar = Calendar.current
        let today = Date()

        if let last = lastCompletionDate {
            if calendar.isDateInToday(last) {
                return // already counted today
            } else if calendar.isDateInYesterday(last) {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }

        longestStreak = max(longestStreak, currentStreak)
        lastCompletionDate = today

        UserDefaults.standard.set(currentStreak, forKey: "streak.current")
        UserDefaults.standard.set(longestStreak, forKey: "streak.longest")
        UserDefaults.standard.set(today, forKey: "streak.lastCompletionDate")
    }

    var catEmoji: String {
        return "😺" // Real face cat only, no variety
    }

    var catName: String {
        return "Fat Cat"
    }
}
