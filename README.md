# 🐈‍⬛ FatCatPomodoro — Detailed Project Documentation
### 📅 Date: Saturday, July 11, 2026
### 🌐 Integration Partner: *Jarvi by AsIfThatWorks* & *SquatAlarm*

---

## 📖 Introduction & Core Concept
**FatCatPomodoro** is an immersive, high-end macOS productivity utility designed specifically for modern Apple Silicon Macbooks. By utilizing a customized transparent window layering technique, the app transforms the physical black bezel notch of the MacBook screen into an interactive, highly responsive, and beautifully animated **"Dynamic Island" Focus Suite**.

The app is built from the ground up to follow **Offline-First** and **B2C-Scalable** architectures, integrating seamlessly with your default calendar and reminder systems locally, while also acting as an interactive bridge to the **Jarvi by AsIfThatWorks** executive RPG cloud platform and the physical **SquatAlarm** fitness dispatcher.

---

## 🚀 Key Functional Capabilities (Indispensable Feature Set)

### 1️⃣ Immersion-First "Dynamic Island" UI
*   **Tucked Wing Mode:** When idle or running, the app shrinks perfectly behind the physical bezel notch. The left wing displays either the remaining time, total configured duration, or system wall clock. The right wing displays your daily completed "Fat Cat" count and streak.
*   **Expanded Management Console:** Hovering or clicking on the tucked island triggers a smooth spring-based frame expansion (`480px` wide) displaying the target dial, task inputs, suggestion chips, and analytics logs.
*   **Adaptive Bezel Integration:** Uses a custom `NotchShape` that ensures the top edges of the expanded bar bleed sharply into the screen's top bezel, making the island look like an organic physical extension of your Mac's screen.
*   **Multi-Monitor Floating Mode:** The app is completely **Notch-Aware**. If dragged or launched on an external screen without a physical camera notch, it automatically switches to a beautiful standalone **"Floating Pill"** shape that sits cleanly below the top menu edge.

### 2️⃣ Seamless Looping Break Player (Alpha Transparency)
*   **True Transparency Backing:** The break player wraps a native macOS `AVPlayerLayer` configured with raw pixel buffer attributes (`kCVPixelFormatType_32BGRA`) and transparent backing layers (`isOpaque = false`). This allows complex transparent-background video formats (HEVC with alpha or ProRes 4444) to render the animated cat floating seamlessly over your active desktop files.
*   **The "Walk-In" Loop Engine:** To preserve perfect looping immersion, the custom player logic plays the video from `0:00` for the first **`7:09` seconds** (where the cat walks onto the screen). Upon hitting the video end, the player catches the notification and instantly seeks back to exactly `7:09` seconds, creating a perfect repeating loop from that point onward. The walking sequence only plays once!

### 3️⃣ Accidental Click Protection & Visual confirmation
*   **The 10-Second Rule:** Clicking "Pause" within the first 10 seconds of starting a flow session is treated as an accidental click. The app immediately and silently resets the timer back to your flow duration with **no popups, no annoying dialogs, and no messy tracking leaks**.
*   **Interactive Island Abort:** Clicking pause after 10 seconds simply freezes the timer quietly. To end the session early (abort/dismiss), the user **holds (long-presses) the pause button for 0.8 seconds**. This triggers a beautiful, custom-designed visual choice directly inside the expanded island (replacing the input field):
    *   **📝 Log Progress:** Calculates exact elapsed minutes, logs a `[Task] (Partial)` entry, and credits you.
    *   **🗑️ Discard:** Resets the timer without writing dummy logs to your databases.
    *   **▶️ Resume:** Smoothly sliding the task input back in and unpausing the timer.

### 4️⃣ Premium Typographic Focus Display
*   When focus starts and the console is expanded, the task input field morphs into a spectacular 3-line typographic layout:
    *   **Line 1:** `FOCUSING` (Bold orange, wide tracking spacing, size 9)
    *   **Line 2:** *on* (Light serif font, italicized, size 8)
    *   **Line 3:** `Your Focus Task Name` (Rounded medium sans-serif, crisp white, size 12)

### 5️⃣ "Jarvi by AsIfThatWorks" Webhook & Device Pairing Spec
The app acts as a real-time focus telemetry dispatcher, fully supporting the official pairing and analytics protocols over HTTPS to `https://asifthatworks.com/api/v1`.
*   **⚡ Connect Device (Pairing):** Pasting a pairing token in the settings triggers a `POST /squatalarm/connect-device` sending the token, `platform: macos`, and your local computer's `deviceName` (e.g. *"MacBook Pro"*), prompting an instant link confirmation on Telegram.
*   **🏆 Pomodoro Analytics Logging:** Completing or interrupting a session triggers a `POST /analytics/pomodoro` with detailed JSON payload variables:
    ```json
    {
      "sessionDurationMinutes": 25,
      "focusTaskName": "Software Engineering 2",
      "sessionType": "FLOW",
      "interrupted": false,
      "completedAt": "2026-07-11T19:40:00Z",
      "platform": "macos"
    }
    ```
*   **🚨 Real-Time Lifecycle States:** Fires webhooks to `/flow/event` for state changes, notably **`BREAK_START`**, which tells Jarvi to instantly trigger the physical **SquatAlarm** fitness exercises on your phone!

### 6️⃣ Native EventKit Sync (B2C Scaling Masterclass)
*   Instead of complex, battery-intensive, and hard-to-maintain direct syncing clients for various calendar/task providers, FatCatPomodoro delegates cloud synchronization to macOS.
*   By writing/reading directly to **Apple EventKit (`EKEventStore`)**, FatCatPomodoro gains instant bi-directional access to any calendars or tasks the user has connected to their Mac (iCloud, Google Tasks, Exchange, etc.). 
*   **Calendar Selection:** Settings features a live picker listing all editable macOS calendars, letting you choose exactly where your **`FatCatFlow Session`** logs should be written.
*   **Suggestion Chips:** Active to-dos are pulled automatically and displayed as scrollable capsule chips in the island, allowing **1-click focus loading and automatic completion**.

### 7️⃣ Smart Chime and Alarm Customization
*   **Quiet Transition Chime:** When your focus session ends, the app plays your chosen alarm sound **only once**, keeping the start of your break screen and cat walk-in peaceful.
*   **Loud Looping Alarm:** When the break ends (or is skipped), the alarm loops continuously and aggressively triggers `NSApp.requestUserAttention(.criticalRequest)` to make the Dock icon bounce, forcing you back to work until you click "DONE" on the center drop-down popup.

### 8️⃣ Premium Integrated Analytics
*   The Settings panel places user analytics right at the **very top** where they are most visible.
*   Features a sleek, dynamically scaling **Last 7 Days Bar Chart** showing completed focus minutes, alongside today's chronological focus logs.
*   Includes a **Desktop CSV Export** utility to let users own and analyze their focus history in external apps.

### 9️⃣ System-Wide Hotkeys
*   Carbon-backed global keybinds operate system-wide even when another app is full-screen:
    *   `Cmd + Shift + L` $\rightarrow$ Expand/Collapse the notch.
    *   `Cmd + Shift + S` $\rightarrow$ Play/Pause the focus timer.

---

## 🛠️ Architecture & Tech Stack
*   **Platform:** macOS 14.0+ (SwiftUI, AppKit, Carbon, EventKit, AVFoundation, Security)
*   **IDE Support:** Fully configured Swift Package Manager structure (`Package.swift`).
*   **Keychain Storage:** Employs native `SecItem` encryption wrappers to store paired Jarvi JWT tokens securely within the system's keychain services.
*   **Multi-Threading:** Uses custom Combine publishers and MainActor dispatch blocks to guarantee thread-safe layout state updates.

---

## 💾 How to Build and Run

To compile and package the app manually inside the native `.app` bundle (ensuring the embedded URL scheme is registered and the transparent cat video resource loads correctly):

```bash
# 1. Build the executable
swift build

# 2. Package the app structure
mkdir -p .build/FatCatPomodoro.app/Contents/MacOS
mkdir -p .build/FatCatPomodoro.app/Contents/Resources

# 3. Copy files & plist
cp .build/arm64-apple-macosx/debug/FatCatPomodoro .build/FatCatPomodoro.app/Contents/MacOS/
cp Sources/FatCatPomodoro/Info.plist .build/FatCatPomodoro.app/Contents/
cp -R .build/arm64-apple-macosx/debug/FatCatPomodoro_FatCatPomodoro.bundle .build/FatCatPomodoro.app/Contents/Resources/

# 4. Register the URL scheme with Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f .build/FatCatPomodoro.app

# 5. Run the app
open .build/FatCatPomodoro.app
```

---

## 🗺️ Future Roadmap
1.  **Strict Mode Network Extension:** Adding a lightweight network filter to hard-block domains directly at the system socket layer.
2.  **Adaptive Focus Scheduling:** Let Grim AI push direct calendar updates that dynamically scale block sizes in real-time based on your cognitive fatigue.
