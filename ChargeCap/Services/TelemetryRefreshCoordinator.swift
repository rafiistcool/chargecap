import Foundation

@MainActor
protocol TelemetryRefreshControlling: AnyObject {
    func updateRefreshInterval(seconds: Int)
    func setInteractiveRefreshEnabled(_ enabled: Bool)
}

@MainActor
final class TelemetryRefreshCoordinator: ObservableObject {
    private let components: [any TelemetryRefreshControlling]
    private var backgroundRefreshIntervalSeconds: Int
    private var isAppActive: Bool
    private var isMenuBarVisible = false

    init(
        components: [any TelemetryRefreshControlling],
        backgroundRefreshIntervalSeconds: Int,
        isAppActive: Bool = false
    ) {
        self.components = components
        self.backgroundRefreshIntervalSeconds = backgroundRefreshIntervalSeconds
        self.isAppActive = isAppActive
        applyRefreshPolicy()
    }

    var isInteractiveRefreshEnabled: Bool {
        isAppActive || isMenuBarVisible
    }

    func updateBackgroundRefreshInterval(seconds: Int) {
        guard backgroundRefreshIntervalSeconds != seconds else { return }
        backgroundRefreshIntervalSeconds = seconds
        applyRefreshPolicy()
    }

    func setAppActive(_ active: Bool) {
        guard isAppActive != active else { return }
        isAppActive = active
        applyRefreshPolicy()
    }

    func setMenuBarVisible(_ visible: Bool) {
        guard isMenuBarVisible != visible else { return }
        isMenuBarVisible = visible
        applyRefreshPolicy()
    }

    private func applyRefreshPolicy() {
        for component in components {
            component.updateRefreshInterval(seconds: backgroundRefreshIntervalSeconds)
            component.setInteractiveRefreshEnabled(isInteractiveRefreshEnabled)
        }
    }
}
