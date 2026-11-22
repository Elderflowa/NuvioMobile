import UIKit

// Routes the mpv video surface to an external display (HDMI/USB-C cable or AirPlay display)
// while the phone keeps showing the player controls.
//
// Flow:
//   1. The system connects a non-interactive external-display scene when a display is attached.
//      `ExternalDisplaySceneDelegate` creates a *hidden* window for it, so ordinary screen
//      mirroring keeps working while the user is browsing.
//   2. While a player exists, the window is shown and the player's CAMetalLayer is re-parented
//      into it, so the video fills the external screen. Without a player the window stays hidden.
//   3. On disconnect or player teardown the layer is moved back to the phone's view.

final class ExternalDisplayCoordinator {
    static let shared = ExternalDisplayCoordinator()

    private weak var player: MPVPlayerViewController?
    private weak var externalWindow: UIWindow?
    private weak var externalHostView: ExternalDisplayHostView?

    private init() {}

    func playerDidStart(_ player: MPVPlayerViewController) {
        self.player = player
        refresh()
    }

    func playerDidStop(_ player: MPVPlayerViewController) {
        guard self.player === player else { return }
        player.detachFromExternalDisplay()
        self.player = nil
        refresh()
    }

    func externalSceneDidConnect(window: UIWindow, hostView: ExternalDisplayHostView) {
        externalWindow = window
        externalHostView = hostView
        refresh()
    }

    func externalSceneDidDisconnect() {
        player?.detachFromExternalDisplay()
        externalWindow = nil
        externalHostView = nil
    }

    private func refresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let player = self.player, let window = self.externalWindow, let host = self.externalHostView {
                window.isHidden = false
                player.attachToExternalDisplay(hostView: host)
            } else {
                self.externalWindow?.isHidden = true
            }
        }
    }
}

final class ExternalDisplayHostView: UIView {
    var onLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

final class ExternalDisplayViewController: UIViewController {
    let hostView = ExternalDisplayHostView()

    override func loadView() {
        view = hostView
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let controller = ExternalDisplayViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.isHidden = true  // stay hidden (system mirroring) until a player is active
        self.window = window

        ExternalDisplayCoordinator.shared.externalSceneDidConnect(window: window, hostView: controller.hostView)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplayCoordinator.shared.externalSceneDidDisconnect()
        window = nil
    }
}
