import SwiftUI
import Combine
import EventKit
import AppKit

enum PomodoroSessionType {
    case work
    case breakTime
}

class PomodoroManager: ObservableObject {
    @Published var timeRemaining: Int = 0
    @Published var isRunning: Bool = false
    @Published var sessionType: PomodoroSessionType = .work
    @Published var completedToday: Int = 0
    @AppStorage("pomodoro.sessionGoal") var sessionGoal: Int = 8
    
    @AppStorage("pomodoro.autoStartWork") var autoStartWork: Bool = false
    @AppStorage("pomodoro.autoStartBreak") var autoStartBreak: Bool = true
    @AppStorage("break.showTimerOverlay") var showBreakTimerOverlay: Bool = true
    @AppStorage("compact.clockMode") var compactClockMode: String = "countdown"
    
    // Pro Settings
    @AppStorage("pomodoro.longBreakDuration") var longBreakDuration: Int = 20 * 60
    @AppStorage("pomodoro.sessionsUntilLongBreak") var sessionsUntilLongBreak: Int = 4
    @AppStorage("pomodoro.sessionsInCycle") var sessionsInCycle: Int = 0
    @AppStorage("pomodoro.dndAutoToggle") var dndAutoToggle: Bool = false
    @AppStorage("pomodoro.alarmSoundName") var alarmSoundName: String = "Glass"
    @AppStorage("pomodoro.alarmVolume") var alarmVolume: Double = 0.8
    @AppStorage("pomodoro.enableReminders") var enableReminders: Bool = false {
        didSet { if enableReminders { fetchReminders() } else { loadRecentTasks() } }
    }
    @AppStorage("pomodoro.strictModeEnabled") var strictModeEnabled: Bool = false
    @AppStorage("pomodoro.targetCalendarID") var targetCalendarID: String = ""
    @AppStorage("pomodoro.calendarSource") var calendarSource: String = "mac"
    @AppStorage("pomodoro.todoSource") var todoSource: String = "jarvi" {
        didSet { fetchReminders() }
    }
    @AppStorage("pomodoro.targetTodoList") var targetTodoList: String = "" {
        didSet { fetchReminders() }
    }
    
    // Alarm state
    @Published var showingAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var isPausedConfirming: Bool = false
    
    // Custom Pomodoro task tracking properties
    @Published var currentTask: String = ""
    @Published var recentTasks: [String] = []
    var sessionStartDate: Date?
    
    // EventKit store for Reminders
    private let eventStore = EKEventStore()
    private var reminderTasks: [String: EKReminder] = [:]
    
    @Published var workDuration: Int = 25 * 60 {
        didSet {
            if !isRunning && sessionType == .work {
                timeRemaining = workDuration
            }
        }
    }
    @Published var breakDuration: Int = 5 * 60 {
        didSet {
            if !isRunning && sessionType == .breakTime {
                timeRemaining = breakDuration
            }
        }
    }
    
    private var timer: AnyCancellable?
    private var lastUpdate: Date?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.timeRemaining = self.workDuration
        
        // Observe history changes to keep counter accurate
        PomodoroHistoryManager.shared.$history
            .receive(on: RunLoop.main)
            .sink { [weak self] history in
                let calendar = Calendar.current
                self?.completedToday = history.filter { calendar.isDateInToday($0.startDate) }.count
            }
            .store(in: &cancellables)
            
        // Observe when available todo lists finish loading in the background on startup, then fetch the tasks
        JarviManager.shared.$availableTodoLists
            .receive(on: RunLoop.main)
            .sink { [weak self] lists in
                guard let self = self else { return }
                if JarviManager.shared.isLinked && self.todoSource == "jarvi" {
                    self.fetchReminders()
                }
            }
            .store(in: &cancellables)

        observeMidnight()
        setupJarviRemoteObserver()
        
        if enableReminders || JarviManager.shared.isLinked {
            fetchReminders()
        } else {
            loadRecentTasks()
        }
    }
    
    private func setupJarviRemoteObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("JarviTokenChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchReminders()
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("JarviTodosUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchReminders()
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("JarviStartPomodoro"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let userInfo = notification.userInfo else { return }
            let title = userInfo["title"] as? String ?? ""
            let workMins = userInfo["workDurationMins"] as? Int ?? 25
            let breakMins = userInfo["breakDurationMins"] as? Int ?? 5
            self.workDuration = workMins * 60
            self.breakDuration = max(0, breakMins) * 60
            self.currentTask = title
            self.sessionType = .work
            self.reset()
            self.start()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("JarviRemoteControl"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let userInfo = notification.userInfo else { return }
            let action = userInfo["action"] as? String ?? ""
            let components = userInfo["components"] as? URLComponents
            
            if action == "/start" {
                let title = components?.queryItems?.first(where: { $0.name == "title" })?.value ?? ""
                let durationStr = components?.queryItems?.first(where: { $0.name == "duration" })?.value
                let isBreak = components?.queryItems?.first(where: { $0.name == "isBreak" })?.value == "true" ||
                              components?.queryItems?.first(where: { $0.name == "type" })?.value == "break"
                
                if let durMins = durationStr, let mins = Int(durMins) {
                    if isBreak {
                        self.breakDuration = mins * 60
                    } else {
                        self.workDuration = mins * 60
                    }
                }
                
                self.currentTask = isBreak ? "" : title
                self.sessionType = isBreak ? .breakTime : .work
                self.reset()
                self.start()
            } else if action == "/pause" {
                if self.isRunning {
                    self.handleAbortClick()
                }
            } else if action == "/complete" || action == "/stop" {
                if self.isRunning {
                    self.completeSession()
                }
            } else if action == "/discard" {
                self.discardAndReset()
            }
        }
    }
    
    private func loadRecentTasks() {
        recentTasks = UserDefaults.standard.stringArray(forKey: "pomodoro.recentTasks") ?? []
    }
    
    func fetchReminders() {
        if !enableReminders && !JarviManager.shared.isLinked {
            loadRecentTasks()
            return
        }
        if todoSource == "reminders" {
            CalendarManager.shared.fetchRemindersFromEventKit(calendarID: targetTodoList) { [weak self] tasks in
                guard let self = self else { return }
                self.recentTasks = tasks
            }
        } else {
            JarviManager.shared.fetchTodos(list: targetTodoList) { [weak self] tasks in
                guard let self = self else { return }
                self.recentTasks = tasks
            }
        }
    }
    
    private func fetchRemindersInternal() {
        fetchReminders()
    }

    func saveTaskToRecent() {
        if enableReminders || JarviManager.shared.isLinked { return } // Don't mix manual recent tasks with live Jarvi todos
        
        let title = currentTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        recentTasks.removeAll { $0 == title }
        recentTasks.insert(title, at: 0)
        if recentTasks.count > 10 { recentTasks = Array(recentTasks.prefix(10)) }
        UserDefaults.standard.set(recentTasks, forKey: "pomodoro.recentTasks")
    }

    func removeTaskFromRecent(_ title: String) {
        recentTasks.removeAll { $0 == title }
        UserDefaults.standard.set(recentTasks, forKey: "pomodoro.recentTasks")
        
        if todoSource == "reminders" {
            CalendarManager.shared.completeReminder(title: title, calendarID: targetTodoList)
        } else if todoSource != "jarvi" && !JarviManager.shared.isLinked {
            // Only send standalone TASK_COMPLETED webhook if completeGoogleTask was not/will not be called
            JarviManager.shared.sendEvent(type: "TASK_COMPLETED", sessionId: UUID().uuidString, title: title, list: targetTodoList)
        }
        
        if enableReminders {
            fetchReminders() // Refresh Apple Reminders (local, safe to re-fetch immediately)
        }
        // Jarvi todos: skip immediate re-fetch. The local removal above is already correct,
        // and an instant re-fetch races with completeGoogleTask — returning stale or empty
        // data that wipes the whole list.
    }
    
    func completeTask(_ title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskTitle = trimmedTitle.isEmpty ? "Completed Task" : trimmedTitle
        
        // Calculate session durations if this was the active task running, or default duration
        let startDate = sessionStartDate ?? Date().addingTimeInterval(-Double(workDuration))
        let endDate = Date()
        let durationMinutes = sessionStartDate != nil ? max(1, Int(endDate.timeIntervalSince(startDate)) / 60) : max(1, workDuration / 60)
        
        if todoSource == "jarvi" || JarviManager.shared.isLinked {
            JarviManager.shared.completeGoogleTask(taskTitle: taskTitle, listId: targetTodoList, durationMinutes: durationMinutes)
        }
        
        // Log to target calendar when task is marked completed
        let cleanCalendarId = targetCalendarID.isEmpty ? "primary" : targetCalendarID
        if calendarSource == "jarvi" || calendarSource == "google" {
            JarviManager.shared.addGoogleCalendarEvent(title: taskTitle, startDate: startDate, endDate: endDate, calendarId: cleanCalendarId)
        } else {
            CalendarManager.shared.addEvent(title: taskTitle, startDate: startDate, endDate: endDate, calendarIdentifier: targetCalendarID)
        }
        
        // Log to local history database and streak
        let durationSeconds = sessionStartDate != nil ? max(60, Int(endDate.timeIntervalSince(startDate))) : workDuration
        PomodoroHistoryManager.shared.logSession(title: taskTitle, startDate: startDate, endDate: endDate, durationSeconds: durationSeconds)
        StreakManager.shared.recordSession()
        
        // Reset active session state if completing current task
        if currentTask == title {
            if isRunning {
                pause()
            }
            sessionStartDate = nil
            currentTask = ""
        }
        
        removeTaskFromRecent(title)
    }
    
    func completeCurrentTask() {
        let title = currentTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        completeTask(title)
    }

    private func observeMidnight() {
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.completedToday = PomodoroHistoryManager.shared.todaysHistory.count
        }
    }

    func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }
    
    func handleAbortClick() {
        let elapsedSeconds = workDuration - timeRemaining
        
        // If under 10 seconds, immediately discard and reset without prompting
        if elapsedSeconds <= 10 {
            self.discardAndReset()
            return
        }
        
        // Pause the countdown immediately
        pause()
        isPausedConfirming = true
    }
    
    func logPartialProgress() {
        let elapsedSeconds = workDuration - timeRemaining
        guard elapsedSeconds > 10 else {
            discardAndReset()
            return
        }
        
        let startDate = sessionStartDate ?? Date().addingTimeInterval(-Double(elapsedSeconds))
        let endDate = Date()
        let durationMins = elapsedSeconds / 60
        
        let trimmedTask = currentTask.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskTitle = trimmedTask.isEmpty ? "FatCatFlow Session" : trimmedTask
        
        // Log to calendar
        if calendarSource == "jarvi" || calendarSource == "google" {
            JarviManager.shared.addGoogleCalendarEvent(title: "\(taskTitle) (Partial)", startDate: startDate, endDate: endDate, calendarId: targetCalendarID)
        } else {
            CalendarManager.shared.addEvent(title: "\(taskTitle) (Partial)", startDate: startDate, endDate: endDate, calendarIdentifier: targetCalendarID)
        }
        
        // Record local history database
        PomodoroHistoryManager.shared.logSession(title: "\(taskTitle) (Partial)", startDate: startDate, endDate: endDate, durationSeconds: elapsedSeconds)
        
        // Send to Jarvi by AsIfThatWorks
        JarviManager.shared.logPomodoroSession(durationMinutes: max(1, durationMins), taskName: taskTitle, interrupted: true)
        JarviManager.shared.sendEvent(type: "FLOW_PAUSE", sessionId: UUID().uuidString, title: taskTitle, workMins: max(1, durationMins), breakMins: breakDuration / 60)
        
        // Reset everything
        self.reset()
    }
    
    func discardAndReset() {
        // Send a pause/cancel event to Jarvi without saving anything to the calendar/history
        if sessionType == .work {
            JarviManager.shared.sendEvent(type: "FLOW_PAUSE", sessionId: UUID().uuidString, title: currentTask, workMins: 0, breakMins: breakDuration / 60)
        }
        self.currentTask = ""
        self.reset()
    }
    
    func start() {
        isRunning = true
        isPausedConfirming = false
        lastUpdate = Date()

        if sessionType == .work {
            if sessionStartDate == nil {
                sessionStartDate = Date()
                saveTaskToRecent()
            }
            if dndAutoToggle { NotificationManager.shared.setDND(enabled: true) }
            JarviManager.shared.sendFatcatEvent("FLOW_START", title: currentTask, workDurationMins: workDuration / 60, breakDurationMins: breakDuration / 60)
        } else {
            // It's a break
            JarviManager.shared.sendFatcatEvent("BREAK_START")
        }
        
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    func pause() {
        if isRunning {
            if sessionType == .work {
                JarviManager.shared.sendEvent(type: "FLOW_PAUSE", sessionId: UUID().uuidString, title: currentTask, workMins: workDuration / 60, breakMins: breakDuration / 60)
            } else {
                JarviManager.shared.sendEvent(type: "BREAK_PAUSE", sessionId: UUID().uuidString, title: currentTask, workMins: workDuration / 60, breakMins: breakDuration / 60)
            }
        }
        isRunning = false
        timer?.cancel()
        timer = nil
        if dndAutoToggle { NotificationManager.shared.setDND(enabled: false) }
    }
    
    func reset() {
        pause()
        isPausedConfirming = false
        sessionStartDate = nil
        if sessionType == .work {
            timeRemaining = workDuration
        } else {
            timeRemaining = breakDuration
        }
    }
    
    func skip() {
        isPausedConfirming = false
        if sessionType == .work {
            completeSession()
        } else {
            startWorkSession()
        }
    }
    
    private func tick() {
        if timeRemaining > 0 {
            timeRemaining -= 1
            if strictModeEnabled && sessionType == .work && timeRemaining % 5 == 0 {
                enforceStrictMode()
            }
        } else {
            if sessionType == .work {
                completeSession()
            } else {
                startWorkSession()
            }
        }
    }
    
    private func enforceStrictMode() {
        let script = """
        set blocklist to {"youtube.com", "twitter.com", "x.com", "facebook.com", "reddit.com", "instagram.com"}
        
        -- Safari
        if application "Safari" is running then
            tell application "Safari"
                set winList to every window
                repeat with win in winList
                    set tabList to every tab of win
                    repeat with t in tabList
                        set tabURL to URL of t
                        repeat with blockedDomain in blocklist
                            if tabURL contains blockedDomain then
                                close t
                                exit repeat
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end if
        
        -- Google Chrome
        if application "Google Chrome" is running then
            tell application "Google Chrome"
                set winList to every window
                repeat with win in winList
                    set tabList to every tab of win
                    repeat with t in tabList
                        set tabURL to URL of t
                        repeat with blockedDomain in blocklist
                            if tabURL contains blockedDomain then
                                close t
                                exit repeat
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end if
        """
        
        DispatchQueue.global(qos: .background).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
    }
    
    private func completeSession() {
        pause()
        isPausedConfirming = false
        if sessionType == .work {
            sessionsInCycle += 1
            
            let trimmedTask = currentTask.trimmingCharacters(in: .whitespacesAndNewlines)
            let taskTitle = trimmedTask.isEmpty ? "FatCatFlow Session" : trimmedTask
            
            JarviManager.shared.logPomodoroSession(durationMinutes: workDuration / 60, taskName: taskTitle, interrupted: false)
            JarviManager.shared.sendFatcatEvent("COMPLETED")

            // If not linked to Jarvi, we send FLOW_END as a fallback webhook.
            // If linked, logPomodoroSession (analytics) and the Calendar block are sufficient.
            if !(todoSource == "jarvi" || JarviManager.shared.isLinked) {
                JarviManager.shared.sendEvent(type: "FLOW_END", sessionId: UUID().uuidString, title: taskTitle, workMins: workDuration / 60, breakMins: breakDuration / 60)
            }
            
            // Capture date bounds and durations
            let startDate = sessionStartDate ?? Date().addingTimeInterval(-Double(workDuration))
            let endDate = Date()
            let duration = Int(endDate.timeIntervalSince(startDate))
            
            // Trigger calendar event creation based on selected source
            let cleanCalendarId = targetCalendarID.isEmpty ? "primary" : targetCalendarID
            if calendarSource == "jarvi" || calendarSource == "google" {
                JarviManager.shared.addGoogleCalendarEvent(title: taskTitle, startDate: startDate, endDate: endDate, calendarId: cleanCalendarId)
            } else {
                CalendarManager.shared.addEvent(title: taskTitle, startDate: startDate, endDate: endDate, calendarIdentifier: targetCalendarID)
            }
            
            // Record local history database
            PomodoroHistoryManager.shared.logSession(title: taskTitle, startDate: startDate, endDate: endDate, durationSeconds: duration)
            StreakManager.shared.recordSession()
            
            sessionStartDate = nil
            
            alertTitle = "Flow Session Complete 😺"
            alertMessage = sessionsInCycle >= sessionsUntilLongBreak ? "Time for a LONG break! You earned it." : "Time for a break! Your fat cat is waiting."
            showingAlert = true
            
            NotificationManager.shared.sessionComplete(isBreak: true)
            sessionType = .breakTime
            
            if sessionsInCycle >= sessionsUntilLongBreak {
                timeRemaining = longBreakDuration
                sessionsInCycle = 0 // Reset cycle
            } else {
                timeRemaining = breakDuration
            }
            
            if autoStartBreak { start() }
        } else {
            startWorkSession()
        }
    }
    
    private func startWorkSession() {
        pause()
        isPausedConfirming = false
        
        JarviManager.shared.sendEvent(type: "BREAK_END", sessionId: UUID().uuidString, title: "Break", workMins: workDuration / 60, breakMins: breakDuration / 60)
        
        currentTask = ""
        sessionStartDate = nil
        
        alertTitle = "Break's Over 😸"
        alertMessage = "Ready for another flow session?"
        showingAlert = true
        
        NotificationManager.shared.sessionComplete(isBreak: false)
        sessionType = .work
        timeRemaining = workDuration
        if autoStartWork { start() }
    }
    
    var timeString: String {
        let totalSeconds = abs(timeRemaining)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var progress: Double {
        let total = sessionType == .work ? Double(workDuration) : Double(breakDuration)
        guard total > 0 else { return 0 }
        return 1.0 - (Double(timeRemaining) / total)
    }
}
