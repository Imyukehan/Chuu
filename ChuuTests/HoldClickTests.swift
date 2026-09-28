import XCTest
@testable import Chuu

final class HoldClickTests: XCTestCase {
    private var phases: [InputPhase] = []
    private var time: TimeInterval = 0
    private var pid: pid_t? = 42
    private var held = true
    private var controller: HoldClickController!

    override func setUp() {
        super.setUp()
        phases = []
        time = 0
        pid = 42
        held = true
        controller = HoldClickController(observeSystemEvents: false,
            clock: { self.time }, frontmostPID: { self.pid }, emit: { self.phases.append($0) })
    }

    override func tearDown() {
        controller.stop()
        controller = nil
        super.tearDown()
    }

    private func start(_ rate: HoldClickRate = .normal) -> UUID {
        controller.start(rate: rate, held: { self.held })
    }

    func testStartsImmediatelyAndPairsDownUp() {
        let id = start()
        XCTAssertEqual(phases, [.down])
        time = 0.05
        controller.tick(session: id)
        time = 0.10
        controller.tick(session: id)
        controller.stop(session: id)
        XCTAssertEqual(phases, [.down, .up, .down, .up])
        controller.tick(session: id)
        XCTAssertEqual(phases.count, 4)
        XCTAssertNil(controller.sessionID)
    }

    func testStopDuringUpDoesNotEmitExtraRelease() {
        let id = start()
        controller.tick(session: id)
        controller.stop(session: id)
        controller.stop()
        XCTAssertEqual(phases, [.down, .up])
    }

    func testMissingUpIsRecoveredFromPhysicalState() {
        let id = start()
        held = false
        controller.tick(session: id)
        XCTAssertEqual(phases, [.down, .up])
        XCTAssertNil(controller.sessionID)
    }

    func testAppSwitchCancelsAndDoesNotResumeOnReturn() {
        let id = start()
        pid = 43
        controller.tick(session: id)
        pid = 42
        controller.tick(session: id)
        XCTAssertEqual(phases, [.down, .up])
        XCTAssertNil(controller.sessionID)
    }

    func testStalledRunLoopCancelsInsteadOfCatchingUp() {
        let id = start()
        time = 2
        controller.tick(session: id)
        XCTAssertEqual(phases, [.down, .up])
        XCTAssertNil(controller.sessionID)
    }

    func testOldReleaseAndQueuedTicksCannotAffectNewHold() {
        let old = start()
        let current = start(.fast)
        controller.stop(session: old)
        controller.tick(session: old)
        XCTAssertEqual(controller.sessionID, current)
        XCTAssertEqual(phases, [.down, .up, .down])
        controller.stop(session: current)
        XCTAssertEqual(phases, [.down, .up, .down, .up])
    }

    func testTimerActuallyRepeatsAndStaysStopped() {
        let id = start(.fastest)
        RunLoop.main.run(until: Date().addingTimeInterval(0.16))
        XCTAssertGreaterThanOrEqual(phases.count, 3)
        controller.stop(session: id)
        let count = phases.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        XCTAssertEqual(phases.count, count)
        XCTAssertEqual(phases.last, .up)
    }

    func testRatesResolveAndBindingsRoundTrip() throws {
        for rate in HoldClickRate.allCases {
            let shortcut = SystemShortcut.autoClickShortcut(rate)
            XCTAssertEqual(SystemShortcut.getShortcut(named: rate.identifier), shortcut)
            XCTAssertEqual(shortcut.executionMode, .stateful)
            XCTAssertNotEqual(shortcut.localizedName, shortcut.identifier)
            guard case .autoClick(let resolved) = ShortcutExecutor.shared.resolveAction(named: rate.identifier) else {
                return XCTFail("Missing auto-click action")
            }
            XCTAssertEqual(resolved, rate)
            let binding = ButtonBinding(triggerEvent: RecordedEvent(type: .mouse, code: 5,
                modifiers: 0, displayComponents: ["Mouse 5"], deviceFilter: nil), systemShortcutName: rate.identifier)
            let decoded = try JSONDecoder().decode(ButtonBinding.self, from: JSONEncoder().encode(binding))
            XCTAssertEqual(decoded.systemShortcutName, rate.identifier)
        }
        XCTAssertNil(HoldClickRate(identifier: "mouseAutoClick0"))
        XCTAssertNil(HoldClickRate(identifier: "mouseAutoClick1000"))
        XCTAssertNil(SystemShortcut.displayShortcut(matchingBindingName: "custom::65531:10"))
        XCTAssertNotEqual(SystemShortcut.localizedCategoryName("categoryHoldAutoClick"), "categoryHoldAutoClick")
    }

    func testMenuContainsAllFourEnabledRates() {
        let menu = NSMenu()
        ShortcutManager.buildShortcutMenu(into: menu, target: NSObject(), action: NSSelectorFromString("selectAction:"))
        let items = menu.items.flatMap { $0.submenu?.items ?? [] }.filter {
            guard let shortcut = $0.representedObject as? SystemShortcut.Shortcut else { return false }
            return HoldClickRate(identifier: shortcut.identifier) != nil
        }
        XCTAssertEqual(items.count, 4)
        XCTAssertTrue(items.allSatisfy(\.isEnabled))
        XCTAssertTrue(items.allSatisfy { $0.image != nil })
    }
}
