import SwiftUI
import AppKit
import Combine

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "islandbar"))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: IslandWindow?
    var fullScreenWindow: NSWindow?
    var skipButtonWindow: NSWindow?
    var breakTimerWindow: NSWindow?
    var alertWindow: NSWindow?
    let pomodoroManager = PomodoroManager()
    private var cancellables = Set<AnyCancellable>()

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            JarviManager.shared.handleDeepLink(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let iconURL = Bundle.main.url(forResource: "FatCatPomodoro", withExtension: "png") ?? Bundle.module.url(forResource: "FatCatPomodoro", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }

        let contentView = IslandView(pomodoroManager: pomodoroManager, isNotchedDisplay: isNotchedDisplay)
        window = IslandWindow(contentView: AnyView(contentView))

        positionWindow()
        window?.makeKeyAndOrderFront(nil)

        setupFullScreenObserver()
        setupAlertObserver()
        setupScreenChangeObserver()
        setupHotkeys()
    }
    
    private func setupHotkeys() {
        HotkeyManager.shared.onToggleTimer = { [weak self] in
            DispatchQueue.main.async {
                self?.pomodoroManager.toggle()
            }
        }
        HotkeyManager.shared.onToggleExpansion = {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("ToggleIslandExpansion"), object: nil)
            }
        }
        HotkeyManager.shared.setup()
    }

    // Prefer the built-in MacBook display so the Island aligns with the physical notch
    private var notchScreen: NSScreen {
        let builtIn = NSScreen.screens.first {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
        return builtIn ?? NSScreen.main ?? NSScreen.screens[0]
    }
    
    var isNotchedDisplay: Bool {
        // A simple heuristic: most recent MacBook Pros have safe areas that imply a notch.
        // We can check the safeAreaInsets of the notchScreen.
        let screen = notchScreen
        return screen.safeAreaInsets.top > 0
    }

    private func positionWindow() {
        let screen = notchScreen
        let r = screen.frame
        let w: CGFloat = 600
        let h: CGFloat = 420
        let yOffset: CGFloat = isNotchedDisplay ? 0 : -10 // Float slightly below top edge if no notch
        window?.setFrame(NSRect(x: r.midX - w / 2, y: r.maxY - h + yOffset, width: w, height: h), display: true)
    }

    private func setupScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.positionWindow() }
    }

    private func setupAlertObserver() {
        pomodoroManager.$showingAlert
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                // The Top Pill (ForegroundAlertView) doesn't have to show up
                /*
                if show {
                    self?.showForegroundAlert()
                } else
                */
                if !show {
                    self?.hideForegroundAlert()
                }
            }
            .store(in: &cancellables)
    }

    private func showForegroundAlert() {
        if alertWindow == nil {
            let screen = notchScreen
            let w: CGFloat = 500
            let h: CGFloat = 160
            let alertWin = NSWindow(
                contentRect: NSRect(x: screen.frame.midX - w / 2,
                                   y: screen.frame.maxY - h - 100,
                                   width: w, height: h),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            alertWin.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 5)
            alertWin.backgroundColor = .clear
            alertWin.isOpaque = false
            alertWin.hasShadow = true
            alertWin.ignoresMouseEvents = false
            alertWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            alertWin.contentView = IslandHostingView(rootView: ForegroundAlertView(pomodoroManager: pomodoroManager))
            self.alertWindow = alertWin
        }
        NSApp.activate(ignoringOtherApps: true)
        alertWindow?.orderFrontRegardless()
    }

    private func hideForegroundAlert() {
        NotificationManager.shared.stopAlarm()
        alertWindow?.orderOut(nil)
        alertWindow = nil
    }

    private func setupFullScreenObserver() {
        pomodoroManager.$isRunning
            .combineLatest(pomodoroManager.$sessionType)
            .sink { [weak self] isRunning, sessionType in
                let shouldShow = isRunning && sessionType == .breakTime
                if shouldShow {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if self?.pomodoroManager.isRunning == true && self?.pomodoroManager.sessionType == .breakTime {
                            self?.updateFullScreenVideo(show: true)
                        }
                    }
                } else {
                    self?.updateFullScreenVideo(show: false)
                }
            }
            .store(in: &cancellables)

        // React live when user toggles the break timer setting mid-break
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  self.pomodoroManager.isRunning,
                  self.pomodoroManager.sessionType == .breakTime else { return }
            self.syncBreakTimerOverlay()
        }
    }

    private func updateFullScreenVideo(show: Bool) {
        if show {
            if fullScreenWindow == nil {
                let screen = notchScreen

                // Cat video — full screen, click-through, transparent background
                let catWin = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                catWin.level = .mainMenu - 1
                catWin.backgroundColor = .clear
                catWin.isOpaque = false
                catWin.hasShadow = false
                catWin.ignoresMouseEvents = true
                catWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                catWin.contentView = NSHostingView(
                    rootView: LoopingVideoPlayer(videoName: "cleancat", videoType: "mov").ignoresSafeArea()
                )
                self.fullScreenWindow = catWin

                // Skip pill — bottom center, clickable
                let btnW: CGFloat = 140
                let btnH: CGFloat = 38
                let skipWin = NSWindow(
                    contentRect: NSRect(x: screen.frame.midX - btnW / 2,
                                       y: screen.frame.minY + 28,
                                       width: btnW, height: btnH),
                    styleMask: [.borderless, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                skipWin.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
                skipWin.backgroundColor = .clear
                skipWin.isOpaque = false
                skipWin.hasShadow = true
                skipWin.ignoresMouseEvents = false
                skipWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                skipWin.contentView = NSHostingView(rootView: BreakSkipButton(pomodoroManager: pomodoroManager))
                self.skipButtonWindow = skipWin
            }
            fullScreenWindow?.orderFrontRegardless()
            skipButtonWindow?.orderFrontRegardless()
            syncBreakTimerOverlay()
        } else {
            fullScreenWindow?.orderOut(nil);  fullScreenWindow = nil
            skipButtonWindow?.orderOut(nil);  skipButtonWindow = nil
            breakTimerWindow?.orderOut(nil);  breakTimerWindow = nil
        }
    }

    // Break timer overlay — top-left, translucent
    private func syncBreakTimerOverlay() {
        guard pomodoroManager.showBreakTimerOverlay else {
            breakTimerWindow?.orderOut(nil)
            breakTimerWindow = nil
            return
        }
        let screen = notchScreen
        let savedX = UserDefaults.standard.double(forKey: "pomodoro.breakOverlayX")
        let savedY = UserDefaults.standard.double(forKey: "pomodoro.breakOverlayY")
        let defaultX = screen.frame.origin.x + 24
        let defaultY = screen.frame.maxY - 180 - 24
        var startX = savedX != 0 ? savedX : defaultX
        var startY = savedY != 0 ? savedY : defaultY
        
        // Safety validation: Ensure the overlay window remains on screen
        if startY + 180 > screen.frame.maxY || startY < screen.frame.origin.y {
            startY = defaultY
        }
        if startX < screen.frame.origin.x || startX + 380 > screen.frame.maxX {
            startX = defaultX
        }
        
        if breakTimerWindow == nil {
            let w: CGFloat = 380, h: CGFloat = 180
            let timerWin = DraggableOverlayWindow(
                contentRect: NSRect(x: startX, y: startY, width: w, height: h),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            timerWin.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            timerWin.backgroundColor = .clear
            timerWin.isOpaque = false
            timerWin.hasShadow = false
            timerWin.isMovableByWindowBackground = true
            timerWin.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            timerWin.contentView = NSHostingView(rootView: BreakTimerOverlay(pomodoroManager: pomodoroManager, window: timerWin))
            self.breakTimerWindow = timerWin
        }
        breakTimerWindow?.orderFrontRegardless()
    }
}

class DraggableOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        UserDefaults.standard.set(frame.origin.x, forKey: "pomodoro.breakOverlayX")
        UserDefaults.standard.set(frame.origin.y, forKey: "pomodoro.breakOverlayY")
    }
}

// MARK: - Break Screen Views

struct ForegroundAlertView: View {
    @ObservedObject var pomodoroManager: PomodoroManager

    var body: some View {
        HStack(spacing: 24) {
            let alarmImage = Image(systemName: "alarm.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            if #available(macOS 15.0, *) {
                alarmImage.symbolEffect(.bounce, options: .repeating)
            } else {
                alarmImage
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pomodoroManager.alertTitle)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text(pomodoroManager.alertMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Button(action: {
                pomodoroManager.showingAlert = false
            }) {
                Text("DONE")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(Capsule())
                    .shadow(color: .orange.opacity(0.4), radius: 10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.black.opacity(0.9))
                
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(LinearGradient(colors: [.orange, .orange.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            }
        }
    }
}

struct BreakSkipButton: View {
    let pomodoroManager: PomodoroManager

    var body: some View {
        Button(action: { pomodoroManager.skip() }) {
            HStack(spacing: 6) {
                Text("Skip Break")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Image(systemName: "forward.fill")
                    .font(.system(size: 10))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct BreakTimerOverlay: View {
    @ObservedObject var pomodoroManager: PomodoroManager
    weak var window: NSWindow?
    @AppStorage("pomodoro.breakOverlayScale") private var scale: Double = 1.0
    @State private var isPulsing = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // A glowing orange dot indicating active state
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .shadow(color: .orange.opacity(0.6), radius: 4)
                .opacity(isPulsing ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("REST TIME")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                        .tracking(1.5)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    if isHovering {
                        HStack(spacing: 4) {
                            Button(action: {
                                scale = max(0.65, scale - 0.1)
                            }) {
                                Image(systemName: "minus")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                scale = min(1.8, scale + 0.1)
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .transition(.opacity)
                    }
                }

                Text(pomodoroManager.timeString)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.85))
                Capsule()
                    .stroke(LinearGradient(colors: [.orange.opacity(0.4), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
        }
        .scaleEffect(scale, anchor: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hover
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { val in
                    scale = min(1.8, max(0.65, scale * val))
                }
        )
        .onAppear {
            isPulsing = true
        }
    }
}
