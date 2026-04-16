import XCTest
@testable import ChargeCap

@MainActor
final class ProManagerTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ProManagerTests")!
        defaults.removePersistentDomain(forName: "ProManagerTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ProManagerTests")
        defaults = nil
        super.tearDown()
    }

    // MARK: - PurchaseState Equatable

    func testPurchaseState_idle_equatable() {
        XCTAssertEqual(ProManager.PurchaseState.idle, ProManager.PurchaseState.idle)
    }

    func testPurchaseState_purchased_equatable() {
        XCTAssertEqual(ProManager.PurchaseState.purchased, ProManager.PurchaseState.purchased)
    }

    func testPurchaseState_pending_equatable() {
        XCTAssertEqual(ProManager.PurchaseState.pending, ProManager.PurchaseState.pending)
    }

    func testPurchaseState_cancelled_equatable() {
        XCTAssertEqual(ProManager.PurchaseState.cancelled, ProManager.PurchaseState.cancelled)
    }

    func testPurchaseState_failed_equatable() {
        XCTAssertEqual(
            ProManager.PurchaseState.failed("error"),
            ProManager.PurchaseState.failed("error")
        )
    }

    func testPurchaseState_differentFailed_notEqual() {
        XCTAssertNotEqual(
            ProManager.PurchaseState.failed("error1"),
            ProManager.PurchaseState.failed("error2")
        )
    }

    func testPurchaseState_differentCases_notEqual() {
        XCTAssertNotEqual(ProManager.PurchaseState.idle, ProManager.PurchaseState.purchased)
        XCTAssertNotEqual(ProManager.PurchaseState.pending, ProManager.PurchaseState.cancelled)
        XCTAssertNotEqual(ProManager.PurchaseState.idle, ProManager.PurchaseState.failed("x"))
    }

    // MARK: - Initialization

    func testInit_defaultState() {
        let manager = ProManager(defaults: defaults)
        XCTAssertFalse(manager.isLoading)
        XCTAssertEqual(manager.purchaseState, .idle)
        XCTAssertNil(manager.productDisplayPrice)
    }

    #if DEBUG
    func testInit_debugOverrideEnabled_unlockedPro() {
        defaults.set(true, forKey: "proOverrideEnabled")
        let manager = ProManager(defaults: defaults)
        XCTAssertTrue(manager.hasUnlockedPro)
    }

    func testInit_debugOverrideDisabled_lockedPro() {
        defaults.set(false, forKey: "proOverrideEnabled")
        let manager = ProManager(defaults: defaults)
        XCTAssertFalse(manager.hasUnlockedPro)
    }

    func testInit_noDebugOverride_lockedPro() {
        let manager = ProManager(defaults: defaults)
        XCTAssertFalse(manager.hasUnlockedPro)
    }

    // MARK: - Debug Override

    func testSetDebugProOverride_enable() {
        let manager = ProManager(defaults: defaults)
        manager.setDebugProOverride(true)
        XCTAssertTrue(manager.hasUnlockedPro)
        XCTAssertTrue(defaults.bool(forKey: "proOverrideEnabled"))
    }

    func testSetDebugProOverride_disable() {
        let manager = ProManager(defaults: defaults)
        manager.setDebugProOverride(true)
        XCTAssertTrue(manager.hasUnlockedPro)

        manager.setDebugProOverride(false)
        XCTAssertFalse(manager.hasUnlockedPro)
        XCTAssertFalse(defaults.bool(forKey: "proOverrideEnabled"))
    }

    func testSetDebugProOverride_persists() {
        let manager = ProManager(defaults: defaults)
        manager.setDebugProOverride(true)

        // Create new instance to verify persistence
        let manager2 = ProManager(defaults: defaults)
        XCTAssertTrue(manager2.hasUnlockedPro)
    }
    #endif
}
