import SwiftUI

struct IslandView: View {
    @ObservedObject var pomodoroManager: PomodoroManager
    let isNotchedDisplay: Bool
    @ObservedObject private var streakManager = StreakManager.shared
    @State private var isExpanded = false
    @State private var showExpandedContent = false
    @State private var capturedHeight: CGFloat = 295
    @State private var isHovered = false
    @State private var hoverTask: Task<Void, Never>? = nil
    @State private var expandTask: Task<Void, Never>? = nil
    @Namespace private var animation
    @State private var showSettings = false
    @State private var currentTime = Date()
    @State private var displayMode: PomodoroSessionType = .work
    @State private var hoveredTask: String? = nil
    @State private var hoveredCheckmarkTask: String? = nil
    @State private var startSessionHoverTask: Task<Void, Never>? = nil

    // Hold to Quit state
    @State private var quitHoldProgress: CGFloat = 0
    @State private var isHoldingQuit = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    private var currentTimeString: String {
        Self.timeFormatter.string(from: currentTime)
    }

    private struct Dimensions {
        let width: CGFloat
        let height: CGFloat
    }

    private var currentDimensions: Dimensions {
        // Height is captured once at tap time (capturedHeight) — never reads live observables
        // during animation, which would cause CA constraint conflicts → crash.
        if isExpanded {
            return Dimensions(width: 480, height: capturedHeight)
        } else {
            return Dimensions(width: 318, height: 38)
        }
    }

    private var displayTime: String {
        if pomodoroManager.isRunning {
            return pomodoroManager.timeString
        } else {
            let total = displayMode == .work ? pomodoroManager.workDuration : pomodoroManager.breakDuration
            return "\(total / 60)m"
        }
    }

    private func snapshotExpandedHeight() -> CGFloat {
        if pomodoroManager.isRunning || pomodoroManager.isPausedConfirming {
            if pomodoroManager.sessionType == .work {
                // Chips are hidden during an active work session — compact height
                return pomodoroManager.currentTask.isEmpty ? 202 : 172
            }
            return 192
        }
        if displayMode == .breakTime {
            return 262
        }
        let hasRecent = !pomodoroManager.recentTasks.isEmpty
        return hasRecent ? 262 : 238
    }
    
    var body: some View {
        let dim = currentDimensions
        let notchHeight: CGFloat = 32
        let cornerRadius: CGFloat = isExpanded ? 22 : 15

        ZStack(alignment: .top) {
            // Island content layered on top, aligned to top
            ZStack(alignment: .top) {
                // Background Layer — sharp top corners bleed into the physical notch/screen edge;
                // only the bottom corners are rounded, so the island looks like it grows from the bezel.
                NotchShape(bottomRadius: cornerRadius)
                    .fill(Color.black)
                    .overlay(alignment: .top) {
                        // Subtle glow along the very top edge
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 8)
                    }
                    .overlay {
                        // Hold-to-Quit ring
                        if isHoldingQuit && pomodoroManager.sessionType == .breakTime {
                            NotchShape(bottomRadius: cornerRadius)
                                .trim(from: 0, to: quitHoldProgress)
                                .stroke(Color.red, lineWidth: 3)
                        }
                    }
                
                // Content Layer
                if !isExpanded {
                    // Wings: compact content centered in the 38px pill
                    compactPomodoroView
                        .frame(width: dim.width, height: dim.height)
                } else if showExpandedContent {
                    // Expanded: content starts below the notch gap, fills remaining height
                    expandedPomodoroView
                        .padding(.top, notchHeight)
                        .frame(width: dim.width, height: dim.height, alignment: .top)
                        .transition(.opacity)
                        .animation(.easeIn(duration: 0.15), value: showExpandedContent)
                }
                // isExpanded && !showExpandedContent → plain black shell during animation
            }
            .frame(width: dim.width, height: dim.height)
            .clipShape(
                AnyShape(isNotchedDisplay ? AnyShape(NotchShape(bottomRadius: cornerRadius)) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
            )
            // Progress ring
            .overlay {
                if !isExpanded && pomodoroManager.isRunning && !isHoldingQuit {
                    let w = dim.width
                    let h = dim.height
                    let r: CGFloat = 17  // increased from 15 to account for outward shift
                    let offset: CGFloat = 2 // 2px outward shift

                    if isNotchedDisplay {
                        // Traces the notch outline: down right side, across bottom, up left side
                        Path { p in
                            // Sharp top-right corner — start slightly outside
                            p.move(to: CGPoint(x: w + offset, y: 0))
                            // Straight down the right side
                            p.addLine(to: CGPoint(x: w + offset, y: h - r + offset))
                            // Bottom-right arc
                            p.addArc(center: CGPoint(x: w - r + offset, y: h - r + offset),
                                     radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                            // Across the bottom
                            p.addLine(to: CGPoint(x: r - offset, y: h + offset))
                            // Bottom-left arc
                            p.addArc(center: CGPoint(x: r - offset, y: h - r + offset),
                                     radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
                            // Straight up the left side
                            p.addLine(to: CGPoint(x: -offset, y: 0))
                        }
                        .trim(from: 0, to: pomodoroManager.progress)
                        .stroke(
                            LinearGradient(colors: [.orange, .red], startPoint: .trailing, endPoint: .leading),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                    } else {
                        // Full pill outline for non-notched displays
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .trim(from: 0, to: pomodoroManager.progress)
                            .stroke(
                                LinearGradient(colors: [.orange, .red], startPoint: .trailing, endPoint: .leading),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                            )
                            .frame(width: w + (offset * 2), height: h + (offset * 2))
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    isHovered = true
                } else {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 200_000_000) // Slightly longer delay to prevent jitter
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            isHovered = false
                            // Only collapse when content is fully visible — avoids competing
                            // with the expand animation and the tracking-area false-negative
                            // that fires when the frame grows on tap.
                            if !showSettings && isExpanded {
                                expandTask?.cancel()
                                withAnimation(.easeOut(duration: 0.1)) {
                                    showExpandedContent = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isExpanded = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: showSettings) { _, isShowing in
                if !isShowing && !isHovered {
                    expandTask?.cancel()
                    withAnimation(.easeOut(duration: 0.1)) {
                        showExpandedContent = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    }
                }
            }
            .onTapGesture {
                if isExpanded {
                    expandTask?.cancel()
                    isHovered = false
                    withAnimation(.easeOut(duration: 0.1)) {
                        showExpandedContent = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    }
                } else {
                    // Snapshot height NOW — before animation starts — so the frame size is stable
                    capturedHeight = snapshotExpandedHeight()
                    isHovered = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isExpanded = true
                    }
                    expandTask?.cancel()
                    expandTask = Task {
                        // Wait for the spring animation to mostly finish before fading in content
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            if isHovered {
                                withAnimation(.easeIn(duration: 0.15)) {
                                    showExpandedContent = true
                                }
                            } else {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    isExpanded = false
                                }
                            }
                        }
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pomodoroManager.sessionType == .breakTime && !isHoldingQuit {
                            isHoldingQuit = true
                            withAnimation(.linear(duration: 1.5)) {
                                quitHoldProgress = 1.0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if isHoldingQuit {
                                    pomodoroManager.pause()
                                    pomodoroManager.skip()
                                    isExpanded = false
                                    isHoldingQuit = false
                                    quitHoldProgress = 0
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        isHoldingQuit = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            quitHoldProgress = 0
                        }
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            currentTime = date
        }
        .onChange(of: pomodoroManager.sessionType) { _, newValue in
            displayMode = newValue
        }
        .onChange(of: displayMode) { _, _ in
            if isExpanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    capturedHeight = snapshotExpandedHeight()
                }
            }
        }
        .onChange(of: pomodoroManager.isRunning) { _, _ in
            if isExpanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    capturedHeight = snapshotExpandedHeight()
                }
            }
        }
        .onChange(of: pomodoroManager.isPausedConfirming) { _, _ in
            if isExpanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    capturedHeight = snapshotExpandedHeight()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleIslandExpansion"))) { _ in
            toggleExpansion()
        }
    }
    
    private func toggleExpansion() {
        if isExpanded {
            expandTask?.cancel()
            isHovered = false
            withAnimation(.easeOut(duration: 0.1)) {
                showExpandedContent = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded = false
                }
            }
        } else {
            capturedHeight = snapshotExpandedHeight()
            isHovered = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isExpanded = true
            }
            expandTask?.cancel()
            expandTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if isHovered {
                        withAnimation(.easeIn(duration: 0.15)) {
                            showExpandedContent = true
                        }
                    }
                }
            }
        }
    }
    
    // Invisible in tucked state — sits perfectly behind the physical notch
    var tuckedNotchView: some View {
        EmptyView()
    }

    // Wings: time on the left, cats on the right — same height as the notch
    var compactPomodoroView: some View {
        HStack(spacing: 0) {
            // Left wing: show countdown when running, otherwise respect user preference
            Group {
                if pomodoroManager.isRunning {
                    Text(pomodoroManager.timeString)
                } else {
                    switch pomodoroManager.compactClockMode {
                    case "preset":
                        let total = pomodoroManager.sessionType == .work ? pomodoroManager.workDuration : pomodoroManager.breakDuration
                        Text("\(total / 60)m")
                    case "clock":
                        Text(currentTimeString)
                    default:
                        Text(displayTime)
                    }
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(pomodoroManager.isRunning ? .orange.opacity(0.9) : .white.opacity(0.85))
            .monospacedDigit()
            .frame(width: 50, alignment: .center) // increased width for MM:SS

            Spacer() // center 230px = physical notch, stays black

            // Right wing: cat count
            HStack(spacing: 3) {
                CatIconView(emoji: streakManager.catEmoji, size: 20)
                Text("\(pomodoroManager.completedToday)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.orange.opacity(0.9))
            }
            .frame(width: 45, alignment: .center)
        }
    }
    
    var expandedPomodoroView: some View {
        VStack(spacing: 0) {

            // ── TOP ROW ──────────────────────────────────────────────────────
            HStack(spacing: 0) {
                // Left wing: mode switcher
                HStack(spacing: 0) {
                    // Larger F / B segmented switcher
                    HStack(spacing: 4) {
                        ForEach([(label: "FLOW", type: PomodoroSessionType.work),
                                 (label: "BREAK", type: PomodoroSessionType.breakTime)], id: \.label) { item in
                            Button(action: {
                                if pomodoroManager.isRunning || pomodoroManager.isPausedConfirming { return }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    displayMode = item.type
                                    pomodoroManager.sessionType = item.type
                                    pomodoroManager.reset()
                                }
                            }) {
                                Text(item.label)
                                    .font(.system(size: 9, weight: .black))
                                    .frame(width: 44, height: 24)
                                    .background(displayMode == item.type ? Color.orange : Color.clear)
                                    .foregroundColor(displayMode == item.type ? .black : .white.opacity(0.4))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                }
                .frame(width: 110, alignment: .leading)
                .padding(.leading, 14)

                Spacer()

                // Center: Time display (in the physical notch gap area)
                Text(displayTime)
                    .font(.system(size: 22, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .frame(width: 164, alignment: .center)
                    .padding(.top, 10)

                Spacer()

                // Right wing: play/pause + settings
                HStack(spacing: 16) {
                    Button(action: { 
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        pomodoroManager.currentTask = pomodoroManager.currentTask.trimmingCharacters(in: .whitespacesAndNewlines)
                        pomodoroManager.saveTaskToRecent()
                        
                        if pomodoroManager.isPausedConfirming {
                            pomodoroManager.isPausedConfirming = false
                            pomodoroManager.start()
                        } else if pomodoroManager.isRunning {
                            pomodoroManager.pause()
                        } else {
                            if displayMode != pomodoroManager.sessionType {
                                pomodoroManager.sessionType = displayMode
                                pomodoroManager.reset()
                            }
                            pomodoroManager.start()
                        }
                    }) {
                        Image(systemName: (pomodoroManager.isRunning && !pomodoroManager.isPausedConfirming) ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.8)
                            .onEnded { _ in
                                pomodoroManager.handleAbortClick()
                            }
                    )

                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        SettingsQuickSetupView(pomodoroManager: pomodoroManager, isPresented: $showSettings)
                            .frame(width: 300, height: 340)
                    }
                }
                .frame(width: 110, alignment: .trailing)
                .padding(.trailing, 14)
            }
            .frame(height: 48)

            // ── DIVIDER ───────────────────────────────────────────────────────
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 14)

            // ── BODY ─────────────────────────────────────────────────────────
            if displayMode == .work {
                VStack(spacing: 0) {
                    // Duration dial (hidden while running or confirming)
                    if (!pomodoroManager.isRunning && !pomodoroManager.isPausedConfirming) || pomodoroManager.sessionType != .work {
                        HorizontalDialView(
                            value: Binding(
                                get: { pomodoroManager.workDuration / 60 },
                                set: { pomodoroManager.workDuration = $0 * 60 }
                            ),
                            range: 5...120,
                            title: "Flow minutes"
                        )
                        .frame(width: 420, height: 72)
                        .id("work-dial")
                        .padding(.top, 6)
                        .padding(.bottom, 0)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                    }

                    // Task input / Status label / Pause Confirmation
                    Group {
                        if pomodoroManager.isPausedConfirming {
                            // Visual Save/Discard prompt
                            VStack(spacing: 8) {
                                Text("Save focus progress so far?")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                                
                                HStack(spacing: 12) {
                                    Button(action: {
                                        pomodoroManager.logPartialProgress()
                                    }) {
                                        Text("Log Progress")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.orange)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Button(action: {
                                        pomodoroManager.discardAndReset()
                                    }) {
                                        Text("Discard")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Button(action: {
                                        pomodoroManager.isPausedConfirming = false
                                        pomodoroManager.start()
                                    }) {
                                        Text("Resume")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundColor(.white.opacity(0.45))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.vertical, 10)
                            .frame(width: 420)
                            .transition(.opacity)
                        } else if pomodoroManager.isRunning && pomodoroManager.sessionType == .work && !pomodoroManager.currentTask.isEmpty {
                            // Active status label — editable 3-line layout when task is set
                            VStack(spacing: 2) {
                                Text("FOCUSING")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                                    .tracking(1.5)
                                
                                Text("on")
                                    .font(.system(size: 8, weight: .light, design: .serif))
                                    .italic()
                                    .foregroundColor(.white.opacity(0.4))
                                
                                ZStack {
                                    TextField("", text: $pomodoroManager.currentTask)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.white.opacity(0.95))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .onSubmit {
                                            pomodoroManager.currentTask = pomodoroManager.currentTask.trimmingCharacters(in: .whitespacesAndNewlines)
                                            pomodoroManager.saveTaskToRecent()
                                        }
                                    
                                    HStack(spacing: 6) {
                                        Spacer()
                                        Button(action: {
                                            withAnimation {
                                                pomodoroManager.completeCurrentTask()
                                            }
                                        }) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundColor(.green.opacity(0.85))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Mark task complete")
                                        
                                        Button(action: { pomodoroManager.currentTask = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white.opacity(0.25))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Clear task")
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.vertical, 4)
                            .transition(.opacity)
                        } else {
                            // Task input field (shown when idle OR when running without a task yet)
                            ZStack {
                                if pomodoroManager.currentTask.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "pencil.line")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange.opacity(0.5))
                                        Text(pomodoroManager.isRunning ? "What's your focus? (press Enter to attach)" : "What's your focus?")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.white.opacity(0.25))
                                    }
                                    .transition(.opacity)
                                }

                                TextField(
                                    "",
                                    text: $pomodoroManager.currentTask
                                )
                                .textFieldStyle(PlainTextFieldStyle())
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .onSubmit {
                                    pomodoroManager.currentTask = pomodoroManager.currentTask.trimmingCharacters(in: .whitespacesAndNewlines)
                                    pomodoroManager.saveTaskToRecent()
                                    if !pomodoroManager.isRunning {
                                        displayMode = .work
                                        pomodoroManager.sessionType = .work
                                        pomodoroManager.timeRemaining = pomodoroManager.workDuration
                                        pomodoroManager.start() 
                                    }
                                }

                                if !pomodoroManager.currentTask.isEmpty {
                                    HStack(spacing: 6) {
                                        Spacer()
                                        Button(action: {
                                            withAnimation {
                                                pomodoroManager.completeCurrentTask()
                                            }
                                        }) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundColor(.green.opacity(0.85))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Mark task complete")
                                        
                                        Button(action: { pomodoroManager.currentTask = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white.opacity(0.25))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Clear task")
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                            )
                            .frame(width: 420)
                            .padding(.top, 4)
                            .transition(.opacity)
                        }
                    }

                    // Task chips — hidden while a session is actively running (current task shown above)
                    let isActiveSession = pomodoroManager.isRunning && pomodoroManager.sessionType == .work && !pomodoroManager.currentTask.isEmpty
                    // Today's history titles first (quick re-run), then remaining fetched todos
                    let todayTitles = PomodoroHistoryManager.shared.todaysHistory
                        .map { $0.title }
                        .filter { !$0.hasSuffix("(Partial)") }
                        .reduce(into: [String]()) { acc, t in if !acc.contains(t) { acc.append(t) } }
                    let chipTasks: [String] = {
                        var combined = todayTitles
                        for t in pomodoroManager.recentTasks { if !combined.contains(t) { combined.append(t) } }
                        return Array(combined.prefix(8))
                    }()
                    if !chipTasks.isEmpty && !isActiveSession {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(chipTasks, id: \.self) { title in
                                    HStack(spacing: 0) {

                                        // LEFT ZONE — mark complete
                                        Button {
                                            withAnimation { pomodoroManager.completeTask(title) }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: hoveredCheckmarkTask == title ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 12, weight: hoveredCheckmarkTask == title ? .bold : .semibold))
                                                    .foregroundColor(hoveredCheckmarkTask == title ? .green : .white.opacity(0.35))
                                                if hoveredCheckmarkTask == title {
                                                    Text("Done")
                                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                                        .foregroundColor(.green)
                                                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                                                }
                                            }
                                            .padding(.leading, 9)
                                            .padding(.trailing, 10)
                                            .padding(.vertical, 5)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Mark complete")
                                        .onHover { isHovering in
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                hoveredCheckmarkTask = isHovering ? title : nil
                                            }
                                        }

                                        // Subtle divider between zones
                                        Rectangle()
                                            .fill(Color.white.opacity(0.08))
                                            .frame(width: 1)
                                            .padding(.vertical, 5)

                                        // RIGHT ZONE — start session
                                        Button {
                                            pomodoroManager.currentTask = title
                                            pomodoroManager.saveTaskToRecent()
                                            if !pomodoroManager.isRunning {
                                                displayMode = .work
                                                pomodoroManager.sessionType = .work
                                                pomodoroManager.reset()
                                                pomodoroManager.start()
                                            }
                                        } label: {
                                            Text(title)
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(
                                                    hoveredTask == title ? .orange :
                                                    (pomodoroManager.currentTask == title ? .orange : .white.opacity(0.7))
                                                )
                                                .lineLimit(1)
                                                .padding(.leading, 7)
                                                .padding(.trailing, 10)
                                                .padding(.vertical, 5)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Start session of \(title)")
                                        .onHover { isHovering in
                                            startSessionHoverTask?.cancel()
                                            if isHovering {
                                                startSessionHoverTask = Task {
                                                    try? await Task.sleep(nanoseconds: 120_000_000)
                                                    guard !Task.isCancelled else { return }
                                                    await MainActor.run {
                                                        withAnimation(.easeInOut(duration: 0.15)) {
                                                            hoveredTask = title
                                                        }
                                                    }
                                                }
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    hoveredTask = nil
                                                }
                                            }
                                        }
                                    }
                                    .background(pomodoroManager.currentTask == title ? Color.orange.opacity(0.15) : Color.white.opacity(0.06))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(pomodoroManager.currentTask == title ? Color.orange.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(minWidth: 420, alignment: .center)
                        }
                        .frame(width: 420, height: 32)
                        .padding(.top, 3)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.1),
                                    .init(color: .black, location: 0.9),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    } else {
                         Spacer().frame(height: 8)
                    }
                }
                .padding(.bottom, 2)
            } else {
                // Break — redesigned for parity with Work view
                VStack(spacing: 0) {
                    if (!pomodoroManager.isRunning && !pomodoroManager.isPausedConfirming) || pomodoroManager.sessionType != .breakTime {
                        HorizontalDialView(
                            value: Binding(
                                get: { pomodoroManager.breakDuration / 60 },
                                set: { pomodoroManager.breakDuration = $0 * 60 }
                            ),
                            range: 1...60,
                            title: "Break minutes"
                        )
                        .frame(width: 420, height: 72)
                        .id("break-dial")
                        .padding(.top, 10)
                        .padding(.bottom, 0)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                    }

                    // Break Intention Box
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange.opacity(0.6))

                        Text(pomodoroManager.isRunning && pomodoroManager.sessionType == .breakTime ? "Taking a breather…" : "Ready for a break?")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                    )
                    .frame(width: 420)
                    .padding(.top, (pomodoroManager.isRunning && pomodoroManager.sessionType == .breakTime) ? 12 : 4)

                    // Activity Suggestions (idle only)
                    if !pomodoroManager.isRunning || pomodoroManager.sessionType != .breakTime {
                        HStack(spacing: 8) {
                            ForEach(["Stretch", "Hydrate", "Walk", "Breathe"], id: \.self) { activity in
                                Text(activity)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 12)
                    } else {
                        Spacer().frame(height: 12)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }

            // ── BOTTOM: cats + streak ─────────────────────────────────────────
            HStack {

                ScoreCatView(
                    completed: pomodoroManager.completedToday,
                    goal: pomodoroManager.sessionGoal,
                    catEmoji: streakManager.catEmoji
                )
                Spacer()
                if streakManager.currentStreak > 0 {
                    HStack(spacing: 3) {
                        Text("🔥").font(.system(size: 9))
                        Text("\(streakManager.currentStreak)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.orange)
                        Text(streakManager.currentStreak == 1 ? "day" : "days")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .padding(.bottom, 8)
        }
    }
}

struct SettingsQuickSetupView: View {
    @ObservedObject var pomodoroManager: PomodoroManager
    @Binding var isPresented: Bool
    @ObservedObject var historyManager = PomodoroHistoryManager.shared
    @ObservedObject var launchManager  = LaunchAtLoginManager.shared
    @ObservedObject var calendarManager = CalendarManager.shared
    @ObservedObject var jarviManager = JarviManager.shared
    @State private var pinCode: String = ""
    @State private var isPairingPin: Bool = false
    @State private var pinError: String? = nil
    @State private var showAdvancedSettings: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.orange)
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
            }
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Weekly Stats Chart
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LAST 7 DAYS")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                            .tracking(1)
                        
                        let stats = historyManager.weeklyStats
                        let maxMins = max(1, stats.map { $0.minutes }.max() ?? 1)
                        
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(stats, id: \.day) { stat in
                                VStack(spacing: 4) {
                                    Text("\(stat.minutes)m")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(stat.minutes > 0 ? .orange : .white.opacity(0.3))
                                    
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(stat.minutes > 0 ? Color.orange : Color.white.opacity(0.1))
                                        .frame(width: 24, height: max(4, CGFloat(stat.minutes) / CGFloat(maxMins) * 60))
                                    
                                    Text(stat.day)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 100, alignment: .bottom)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(8)
                    }

                    Divider().background(Color.white.opacity(0.1))
                    
                    // Focus History Log
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("TODAY'S FOCUS LOG")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(1)
                            
                            Spacer()
                            
                            Button("Export CSV") {
                                historyManager.exportCSVToDesktop()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange.opacity(0.9))
                            .padding(.trailing, 8)
                            
                            if !historyManager.todaysHistory.isEmpty {
                                Button("Clear") {
                                    historyManager.clearTodaysHistory()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red.opacity(0.7))
                            }
                        }
                        
                        if historyManager.todaysHistory.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.15))
                                Text("No focus sessions completed today yet.")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.3))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(historyManager.todaysHistory) { item in
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(.white.opacity(0.9))
                                                .lineLimit(1)
                                            
                                            Text(item.timeString)
                                                .font(.system(size: 8))
                                                .foregroundColor(.white.opacity(0.4))
                                        }
                                        
                                        Spacer()
                                        
                                        Text(item.durationMinutesString)
                                            .font(.system(size: 9, weight: .black, design: .rounded))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15))
                                            .cornerRadius(6)
                                    }
                                    .padding(8)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // JARVI Integration
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REMOTE AGENT")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        
                        if jarviManager.isLinked {
                            HStack {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                    Text("Linked to Jarvi by AsIfThatWorks")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                Spacer()
                                Button("↻ Pull Todos") {
                                    pomodoroManager.fetchReminders()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.trailing, 8)

                                Button("Disconnect") {
                                    jarviManager.unlink()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red.opacity(0.8))
                            }
                        } else {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Not Connected")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.5))
                                    Spacer()
                                    Button("⚡ Get PIN (/pair in Telegram)") {
                                        jarviManager.initiatePairing()
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15))
                                    .clipShape(Capsule())
                                }
                                
                                // 6-Digit PIN Input Screen
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Enter 6-Digit PIN from Telegram /pair:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    HStack(spacing: 8) {
                                        TextField("e.g. 123456", text: $pinCode)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(Color.white.opacity(0.08))
                                            .cornerRadius(6)
                                            .onChange(of: pinCode) { _, newValue in
                                                pinError = nil
                                                let filtered = newValue.filter { $0.isNumber }
                                                if filtered.count <= 6 {
                                                    pinCode = filtered
                                                } else {
                                                    pinCode = String(filtered.prefix(6))
                                                }
                                            }
                                        
                                        Button(action: {
                                            guard pinCode.count == 6 else {
                                                pinError = "Enter 6 digits"
                                                return
                                            }
                                            isPairingPin = true
                                            pinError = nil
                                            jarviManager.pairWithPin(pinCode) { success, errorMsg in
                                                isPairingPin = false
                                                if success {
                                                    pinCode = ""
                                                    pinError = nil
                                                } else {
                                                    pinError = errorMsg ?? "Invalid PIN"
                                                }
                                            }
                                        }) {
                                            HStack(spacing: 4) {
                                                if isPairingPin {
                                                    ProgressView()
                                                        .scaleEffect(0.6)
                                                } else {
                                                    Text("Verify PIN")
                                                        .font(.system(size: 10, weight: .black))
                                                }
                                            }
                                            .foregroundColor(pinCode.count == 6 ? .black : .white.opacity(0.4))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(pinCode.count == 6 ? Color.orange : Color.white.opacity(0.1))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .disabled(pinCode.count != 6 || isPairingPin)
                                    }
                                    
                                    if let err = pinError {
                                        Text(err)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(10)
                                .background(Color.orange.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                )
                                
                                HStack {
                                    TextField("Or paste long token directly", text: Binding(
                                        get: { "" },
                                        set: { jarviManager.manualLink(token: $0) }
                                    ))
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(6)
                                    .background(Color.white.opacity(0.03))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Advanced Settings Collapsible Button
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showAdvancedSettings.toggle()
                        }
                    }) {
                        HStack {
                            Text("Advanced Settings")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            Text(showAdvancedSettings ? "Hide" : "Show")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if showAdvancedSettings {
                        advancedSettingsContent
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.95))
        .preferredColorScheme(.dark)
        .onAppear {
            calendarManager.requestAccess()
            calendarManager.requestReminderAccess()
            if jarviManager.isLinked {
                jarviManager.fetchCalendars()
                jarviManager.fetchTodoLists()
            }
        }
        .onChange(of: pomodoroManager.calendarSource) { oldVal, newVal in
            pomodoroManager.targetCalendarID = "" // Reset calendar selection when switching provider
            if newVal == "jarvi" && jarviManager.isLinked {
                jarviManager.fetchCalendars()
            } else if newVal == "mac" {
                calendarManager.fetchCalendars()
            }
        }
        .onChange(of: pomodoroManager.todoSource) { oldVal, newVal in
            pomodoroManager.targetTodoList = "" // Reset todo list selection when switching provider
            if newVal == "jarvi" && jarviManager.isLinked {
                jarviManager.fetchTodoLists()
            } else if newVal == "reminders" {
                calendarManager.fetchTodoLists()
            }
        }
    }

    @ViewBuilder
    private var advancedSettingsContent: some View {
        VStack(spacing: 16) {
            coreTogglesSection
            Divider().background(Color.white.opacity(0.1))
            proRhythmSection
            Divider().background(Color.white.opacity(0.1))
            alarmSection
            Divider().background(Color.white.opacity(0.1))
            calendarSourceSection
            Divider().background(Color.white.opacity(0.1))
            todoSourceSection
            Divider().background(Color.white.opacity(0.1))
            compactClockSection
        }
    }

    @ViewBuilder
    private var coreTogglesSection: some View {
        VStack(spacing: 8) {
            Toggle("Sync JARVI Tasks / Todos", isOn: $pomodoroManager.enableReminders)
            Toggle("Strict Mode (Close Distractions)", isOn: $pomodoroManager.strictModeEnabled)
            Toggle("Auto-Start Work", isOn: $pomodoroManager.autoStartWork)
            Toggle("Auto-Start Break", isOn: $pomodoroManager.autoStartBreak)
            Toggle("DND Auto-Toggle", isOn: $pomodoroManager.dndAutoToggle)
            if pomodoroManager.dndAutoToggle {
                Text("💡 Requires Accessibility permission or a Shortcut named 'Turn Do Not Disturb On' / 'Nicht stören ein'")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(.leading, 18)
            }
            Toggle("Launch at Login", isOn: $launchManager.isEnabled)
            Toggle("Break Timer Overlay", isOn: $pomodoroManager.showBreakTimerOverlay)
        }
        .font(.system(size: 10, weight: .bold))
        .toggleStyle(OrangeToggleStyle())
    }

    @ViewBuilder
    private var proRhythmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRO RHYTHM")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white.opacity(0.4))
            
            HStack {
                Text("Long Break every").font(.system(size: 10, weight: .medium))
                Spacer()
                Stepper("\(pomodoroManager.sessionsUntilLongBreak) sessions", value: $pomodoroManager.sessionsUntilLongBreak, in: 2...10)
                    .font(.system(size: 10, weight: .bold))
            }
            
            HStack {
                Text("Long Break duration").font(.system(size: 10, weight: .medium))
                Spacer()
                Stepper("\(pomodoroManager.longBreakDuration / 60) min", 
                        onIncrement: { pomodoroManager.longBreakDuration += 300 },
                        onDecrement: { if pomodoroManager.longBreakDuration > 300 { pomodoroManager.longBreakDuration -= 300 } })
                    .font(.system(size: 10, weight: .bold))
            }
        }
    }

    @ViewBuilder
    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALARM & SOUND")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white.opacity(0.4))
            
            Picker("Alarm Sound", selection: $pomodoroManager.alarmSoundName) {
                ForEach(["Glass", "Funk", "Morse", "Pop", "Ping", "Sosumi"], id: \.self) {
                    Text($0).tag($0)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume").font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text("\(Int(pomodoroManager.alarmVolume * 100))%").font(.system(size: 9, weight: .bold))
                }
                Slider(value: $pomodoroManager.alarmVolume, in: 0...1)
                    .accentColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var calendarSourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TARGET CALENDAR SOURCE")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white.opacity(0.4))
            
            HStack(spacing: 12) {
                Button(action: { pomodoroManager.calendarSource = "mac" }) {
                    HStack(spacing: 4) {
                        Image(systemName: pomodoroManager.calendarSource == "mac" ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(pomodoroManager.calendarSource == "mac" ? .blue : .white.opacity(0.4))
                        Text("Mac Calendar")
                            .font(.system(size: 10, weight: pomodoroManager.calendarSource == "mac" ? .bold : .regular))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    pomodoroManager.calendarSource = "jarvi"
                    jarviManager.fetchCalendars()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: pomodoroManager.calendarSource == "jarvi" ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(pomodoroManager.calendarSource == "jarvi" ? .orange : .white.opacity(0.4))
                        Text("Google Calendar (JARVI)")
                            .font(.system(size: 10, weight: pomodoroManager.calendarSource == "jarvi" ? .bold : .regular))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if pomodoroManager.calendarSource == "mac" {
                HStack {
                    if calendarManager.availableCalendars.isEmpty {
                        Text("No calendars found or access denied.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Picker("", selection: $pomodoroManager.targetCalendarID) {
                            Text("Default Calendar").tag("")
                            ForEach(calendarManager.availableCalendars, id: \.calendarIdentifier) { calendar in
                                Text(calendar.title).tag(calendar.calendarIdentifier)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .font(.system(size: 10))
                    }
                    Spacer()
                    Button("↻ Refresh") {
                        calendarManager.requestAccess()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.blue)
                }
            } else {
                HStack {
                    if !jarviManager.availableCalendars.isEmpty {
                        Picker("", selection: $pomodoroManager.targetCalendarID) {
                            Text("Primary Google Calendar").tag("")
                            ForEach(jarviManager.availableCalendars, id: \.id) { cal in
                                Text(cal.title).tag(cal.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .font(.system(size: 10))
                    } else if jarviManager.isLinked {
                        Text("No Google calendars found or still loading...")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text("Connect JARVI above to fetch Google Calendars.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    if jarviManager.isLinked {
                        Button("↻ Refresh") {
                            jarviManager.fetchCalendars()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var todoSourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TARGET TODO SOURCE")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white.opacity(0.4))
            
            HStack(spacing: 12) {
                Button(action: {
                    pomodoroManager.todoSource = "reminders"
                    calendarManager.fetchRemindersFromEventKit(calendarID: pomodoroManager.targetTodoList) { tasks in
                        pomodoroManager.recentTasks = tasks
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: pomodoroManager.todoSource == "reminders" ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(pomodoroManager.todoSource == "reminders" ? .blue : .white.opacity(0.4))
                        Text("Apple Reminders")
                            .font(.system(size: 10, weight: pomodoroManager.todoSource == "reminders" ? .bold : .regular))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    pomodoroManager.todoSource = "jarvi"
                    jarviManager.fetchTodoLists()
                    pomodoroManager.fetchReminders()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: pomodoroManager.todoSource == "jarvi" ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(pomodoroManager.todoSource == "jarvi" ? .orange : .white.opacity(0.4))
                        Text("Google Todo (JARVI)")
                            .font(.system(size: 10, weight: pomodoroManager.todoSource == "jarvi" ? .bold : .regular))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if pomodoroManager.todoSource == "reminders" {
                HStack {
                    if calendarManager.availableTodoLists.isEmpty {
                        Text("No reminder lists found.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Picker("", selection: $pomodoroManager.targetTodoList) {
                            Text("All Reminders Lists").tag("")
                            ForEach(calendarManager.availableTodoLists, id: \.calendarIdentifier) { list in
                                Text(list.title).tag(list.calendarIdentifier)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .font(.system(size: 10))
                    }
                    Spacer()
                    Button("↻ Refresh") {
                        calendarManager.requestReminderAccess { _ in
                            pomodoroManager.fetchReminders()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.blue)
                }
            } else {
                HStack {
                    if !jarviManager.availableTodoLists.isEmpty {
                        Picker("", selection: $pomodoroManager.targetTodoList) {
                            Text("All / Default List").tag("")
                            ForEach(jarviManager.availableTodoLists, id: \.id) { list in
                                Text(list.name).tag(list.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .font(.system(size: 10))
                    } else if jarviManager.isLinked {
                        Text("No Google Todo lists found or still loading...")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text("Connect JARVI above to fetch Google Todo Lists.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    if jarviManager.isLinked {
                        Button("↻ Refresh Lists") {
                            jarviManager.fetchTodoLists()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var compactClockSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMPACT CLOCK")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white.opacity(0.4))
            
            Picker("", selection: $pomodoroManager.compactClockMode) {
                Text("Countdown").tag("countdown")
                Text("Preset").tag("preset")
                Text("Wall Clock").tag("clock")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

struct OrangeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Rectangle()
                .foregroundColor(configuration.isOn ? .orange : .white.opacity(0.15))
                .frame(width: 32, height: 18)
                .overlay(
                    Circle()
                        .foregroundColor(.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 7 : -7)
                )
                .cornerRadius(10)
                .onTapGesture {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        configuration.isOn.toggle()
                    }
                }
        }
    }
}

// Sharp top corners, rounded bottom corners — makes the island appear to grow from the physical notch.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
