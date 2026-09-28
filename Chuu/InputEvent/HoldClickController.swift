import Cocoa

enum HoldClickRate: Int, CaseIterable {
    case slow = 5, normal = 10, fast = 15, fastest = 20

    var identifier: String { "mouseAutoClick\(rawValue)" }

    init?(identifier: String) {
        guard let rate = Self.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        self = rate
    }
}

/// Main-run-loop ownership keeps release, cancellation and ticks strictly ordered.
final class HoldClickController {
    private let emit: (InputPhase) -> Void
    private let clock: () -> TimeInterval
    private let frontmostPID: () -> pid_t?
    private var timer: Timer?
    private var held: () -> Bool = { false }
    private var targetPID: pid_t?
    private var lastTick: TimeInterval = 0
    private var isDown = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var sessionID: UUID?

    init(
        observeSystemEvents: Bool = true,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        emit: @escaping (InputPhase) -> Void
    ) {
        self.emit = emit
        self.clock = clock
        self.frontmostPID = frontmostPID
        if observeSystemEvents {
            let workspace = NSWorkspace.shared.notificationCenter
            observe(workspace, NSWorkspace.didActivateApplicationNotification)
            observe(workspace, NSWorkspace.willSleepNotification)
            observe(workspace, NSWorkspace.sessionDidResignActiveNotification)
            observe(.default, NSApplication.willTerminateNotification)
            observe(.default, LogiCenter.sessionChanged)
            observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"))
        }
    }

    deinit {
        timer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }

    @discardableResult
    func start(rate: HoldClickRate, held: @escaping () -> Bool) -> UUID {
        assertMainThread()
        stop()
        let id = UUID()
        sessionID = id
        self.held = held
        targetPID = frontmostPID()
        lastTick = clock()
        isDown = true
        emit(.down)
        // Give games a real down/up interval rather than two events in one instant.
        let timer = Timer(timeInterval: 0.5 / Double(rate.rawValue), repeats: true) { [weak self] _ in
            self?.tick(session: id)
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return id
    }

    func tick(session id: UUID) {
        assertMainThread()
        guard sessionID == id else { return }
        let now = clock()
        guard held(), frontmostPID() == targetPID, now - lastTick < 0.5 else {
            stop()
            return
        }
        lastTick = now
        isDown.toggle()
        emit(isDown ? .down : .up)
    }

    func stop(session id: UUID? = nil) {
        assertMainThread()
        if let id, id != sessionID { return }
        timer?.invalidate()
        timer = nil
        sessionID = nil
        held = { false }
        if isDown {
            isDown = false
            emit(.up)
        }
    }

    static func heldCheck(for event: InputEvent) -> () -> Bool {
        guard case .cgEvent = event.source else {
            // Diverted HID++ buttons are released through InputProcessor, not CG's bitmap.
            return { true }
        }
        let code = event.code
        if event.type == .keyboard {
            return { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code)) }
        }
        return { CGEventSource.buttonState(.hidSystemState, button: CGMouseButton(rawValue: UInt32(code))!) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }
        observers.append((center, token))
    }
}
