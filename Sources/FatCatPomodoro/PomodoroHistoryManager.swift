import Foundation
import AppKit

struct PomodoroHistoryItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let durationSeconds: Int
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
    
    var durationMinutesString: String {
        let minutes = durationSeconds / 60
        return "\(minutes)m"
    }
}

class PomodoroHistoryManager: ObservableObject {
    static let shared = PomodoroHistoryManager()
    
    @Published var history: [PomodoroHistoryItem] = []
    
    private var fileURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldDir = appSupport.appendingPathComponent("IslandBar", isDirectory: true)
        let newDir = appSupport.appendingPathComponent("FatCatPomodoro", isDirectory: true)
        
        // Migrate history directory if needed
        if fm.fileExists(atPath: oldDir.path) && !fm.fileExists(atPath: newDir.path) {
            try? fm.moveItem(at: oldDir, to: newDir)
        }
        
        // Ensure directory exists
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        return newDir.appendingPathComponent("history.json")
    }
    
    private init() {
        loadHistory()
    }
    
    func loadHistory() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([PomodoroHistoryItem].self, from: data) {
            // Ensure UI updates happen on MainActor
            DispatchQueue.main.async {
                self.history = decoded
            }
        }
    }
    
    func logSession(title: String, startDate: Date, endDate: Date, durationSeconds: Int) {
        let newItem = PomodoroHistoryItem(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "FatCatFlow Session" : title,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSeconds
        )
        
        DispatchQueue.main.async {
            self.history.insert(newItem, at: 0) // Newest first
            self.saveHistory()
        }
    }
    
    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(history) {
            try? data.write(to: fileURL)
        }
    }
    
    var todaysHistory: [PomodoroHistoryItem] {
        let calendar = Calendar.current
        return history.filter { calendar.isDateInToday($0.startDate) }
    }
    
    // Aggregates focus minutes for the last 7 days (oldest first)
    var weeklyStats: [(day: String, minutes: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var stats: [(day: String, minutes: Int)] = []
        
        let formatter = DateFormatter()
        formatter.dateFormat = "E" // e.g., Mon, Tue
        
        for i in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let dayName = formatter.string(from: date)
            
            let minutesForDay = history
                .filter { calendar.isDate($0.startDate, inSameDayAs: date) }
                .reduce(0) { $0 + ($1.durationSeconds / 60) }
            
            stats.append((day: dayName, minutes: minutesForDay))
        }
        return stats
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.history.removeAll()
            self.saveHistory()
        }
    }

    func clearTodaysHistory() {
        DispatchQueue.main.async {
            let calendar = Calendar.current
            self.history.removeAll { calendar.isDateInToday($0.startDate) }
            self.saveHistory()
        }
    }
    
    func exportCSVToDesktop() {
        let fileName = "FatCatPomodoro_FocusHistory.csv"
        let fm = FileManager.default
        guard let desktopURL = fm.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        let fileURL = desktopURL.appendingPathComponent(fileName)
        
        var csvText = "Task,Start Time,End Time,Duration (Seconds),Duration (Minutes)\n"
        
        let formatter = ISO8601DateFormatter()
        
        for item in history {
            let safeTitle = item.title.replacingOccurrences(of: ",", with: "")
            let start = formatter.string(from: item.startDate)
            let end = formatter.string(from: item.endDate)
            let row = "\(safeTitle),\(start),\(end),\(item.durationSeconds),\(item.durationSeconds / 60)\n"
            csvText.append(row)
        }
        
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully exported history to \(fileURL.path)")
            
            // Optionally, open the folder or file
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } catch {
            print("Failed to export CSV: \(error)")
        }
    }
}
