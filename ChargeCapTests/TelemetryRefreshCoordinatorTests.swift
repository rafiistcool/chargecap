import XCTest
@testable import ChargeCap

@MainActor
final class TelemetryRefreshCoordinatorTests: XCTestCase {

    func testInit_appliesBackgroundRefreshInterval() {
        let target = MockTelemetryRefreshTarget()

        _ = TelemetryRefreshCoordinator(
            components: [target],
            backgroundRefreshIntervalSeconds: 15
        )

        XCTAssertEqual(target.refreshIntervals, [15])
        XCTAssertEqual(target.interactiveStates, [false])
    }

    func testSetMenuBarVisible_enablesInteractiveRefresh() {
        let target = MockTelemetryRefreshTarget()
        let coordinator = TelemetryRefreshCoordinator(
            components: [target],
            backgroundRefreshIntervalSeconds: 15
        )

        coordinator.setMenuBarVisible(true)

        XCTAssertEqual(target.refreshIntervals.suffix(1), [15])
        XCTAssertEqual(target.interactiveStates.suffix(1), [true])
    }

    func testSetAppActive_keepsInteractiveRefreshAfterMenuBarCloses() {
        let target = MockTelemetryRefreshTarget()
        let coordinator = TelemetryRefreshCoordinator(
            components: [target],
            backgroundRefreshIntervalSeconds: 15
        )

        coordinator.setMenuBarVisible(true)
        coordinator.setAppActive(true)
        coordinator.setMenuBarVisible(false)

        XCTAssertEqual(target.interactiveStates.suffix(1), [true])
    }

    func testUpdateBackgroundRefreshInterval_reappliesCurrentMode() {
        let target = MockTelemetryRefreshTarget()
        let coordinator = TelemetryRefreshCoordinator(
            components: [target],
            backgroundRefreshIntervalSeconds: 15
        )

        coordinator.setAppActive(true)
        coordinator.updateBackgroundRefreshInterval(seconds: 30)

        XCTAssertEqual(target.refreshIntervals.suffix(1), [30])
        XCTAssertEqual(target.interactiveStates.suffix(1), [true])
    }
}

@MainActor
private final class MockTelemetryRefreshTarget: TelemetryRefreshControlling {
    private(set) var refreshIntervals: [Int] = []
    private(set) var interactiveStates: [Bool] = []

    func updateRefreshInterval(seconds: Int) {
        refreshIntervals.append(seconds)
    }

    func setInteractiveRefreshEnabled(_ enabled: Bool) {
        interactiveStates.append(enabled)
    }
}
