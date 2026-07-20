import Foundation
import AppKit
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var alarmSound: NSSound? = NSSound(named: "Glass")

    private override init() {
        super.init()
        setupUserNotifications()
    }

    private func setupUserNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("NotificationManager: UNUserNotificationCenter auth error: \(error.localizedDescription)")
            }
        }
    }

    // Ensure notifications appear even if IslandBar is the foreground/active app
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func sessionComplete(isBreak: Bool) {
        let title = isBreak ? "Flow Session Complete 😺" : "Break's Over 😸"
        let message = isBreak ? "Time for a break! Your fat cat is waiting." : "Ready for another flow session?"
        
        // Show system notification via native UNUserNotificationCenter
        sendNotification(title: title, message: message)
        
        // Custom sound settings
        let soundName = UserDefaults.standard.string(forKey: "pomodoro.alarmSoundName") ?? "Glass"
        let volume = UserDefaults.standard.double(forKey: "pomodoro.alarmVolume")
        
        alarmSound = NSSound(named: soundName)
        alarmSound?.volume = Float(volume == 0 ? 0.8 : volume)
        
        if isBreak {
            // Peaceful transition: play the alert chime ONLY ONCE so the cat video is quiet
            alarmSound?.loops = false
            alarmSound?.play()
        } else {
            // Break's Over: play a chime once to alert the user
            alarmSound?.loops = false
            alarmSound?.play()
            
            // Aggressively pull the app to the front
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.requestUserAttention(.criticalRequest)
            }
        }
    }
    
    func stopAlarm() {
        alarmSound?.stop()
    }

    func setDND(enabled: Bool) {
        print("NotificationManager: Toggling DND (\(enabled ? "ON" : "OFF"))...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Try running common macOS Shortcuts (English & German & user shortcut names)
            let shortcutNames = enabled
                ? ["Turn Do Not Disturb On", "Nicht stören ein", "Ablenkungen verhindern", "Focus On", "DND On"]
                : ["Turn Do Not Disturb Off", "Nicht stören aus", "Ablenkungen zulassen", "Focus Off", "DND Off"]
            
            var shortcutSuccess = false
            for name in shortcutNames {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name]
                do {
                    try process.run()
                    // Use a short timeout to avoid hanging if shortcuts CLI waits
                    let deadline = DispatchTime.now() + 2.0
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        process.waitUntilExit()
                        group.leave()
                    }
                    if group.wait(timeout: deadline) == .success && process.terminationStatus == 0 {
                        print("NotificationManager: Successfully ran shortcut '\(name)'")
                        shortcutSuccess = true
                        break
                    } else if process.isRunning {
                        process.terminate()
                    }
                } catch {
                    continue
                }
            }
            
            // 2. If shortcuts didn't run, fallback to Control Center AppleScript
            if !shortcutSuccess {
                let script = """
                tell application "System Events"
                    if not (exists process "Control Center") then return
                    tell process "Control Center"
                        try
                            click menu bar item "Focus" of menu bar 1
                        on error
                            try
                                click (first menu bar item of menu bar 1 whose description contains "Focus" or description contains "Fokus" or description contains "Stören")
                            end try
                        end try
                        delay 0.3
                        try
                            click (first checkbox of group 1 of window "Control Center" whose title contains "Do Not Disturb" or title contains "Nicht stören")
                        end try
                        delay 0.2
                        key code 53 -- Esc key to close Control Center
                    end tell
                end tell
                """
                
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: script) {
                    appleScript.executeAndReturnError(&error)
                    if let err = error {
                        print("NotificationManager: AppleScript DND toggle error: \(err)")
                    } else {
                        print("NotificationManager: AppleScript DND toggle executed.")
                    }
                }
            }
        }
    }

    private func sendNotification(title: String, message: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                self?.deliverUNNotification(title: title, message: message, center: center)
            } else if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        self?.deliverUNNotification(title: title, message: message, center: center)
                    } else {
                        self?.deliverNSUserNotification(title: title, message: message)
                    }
                }
            } else {
                // Fallback to native NSUserNotification (uses app icon face_cat without osascript scroll)
                self?.deliverNSUserNotification(title: title, message: message)
            }
        }
    }

    private func deliverUNNotification(title: String, message: String, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        if let iconURL = Bundle.main.url(forResource: "face_cat", withExtension: "png") ?? Bundle.module.url(forResource: "face_cat", withExtension: "png"),
           let attachment = try? UNNotificationAttachment(identifier: "face_cat", url: iconURL, options: nil) {
            content.attachments = [attachment]
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { [weak self] error in
            if let error = error {
                print("NotificationManager: Failed UNNotification, falling back: \(error.localizedDescription)")
                self?.deliverNSUserNotification(title: title, message: message)
            }
        }
    }

    private func deliverNSUserNotification(title: String, message: String) {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = message
            notification.soundName = NSUserNotificationDefaultSoundName
            
            if let iconURL = Bundle.main.url(forResource: "FatCatPomodoro", withExtension: "png") ?? Bundle.module.url(forResource: "FatCatPomodoro", withExtension: "png"),
               let iconImage = NSImage(contentsOf: iconURL) {
                notification.contentImage = iconImage
            }
            
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
}

