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

    // MARK: - Loading backdrop

    private var backdropView: UIView?
    private var backdropImageView: UIImageView?

    /// Dimmed artwork with a spinner, shown above the video layer until the first frame is ready.
    func showBackdrop(_ image: UIImage?) {
        guard let image else { return }
        if backdropView == nil {
            let container = UIView(frame: bounds)
            container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.backgroundColor = .black

            let imageView = UIImageView(frame: bounds)
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            container.addSubview(imageView)
            backdropImageView = imageView

            let dim = UIView(frame: bounds)
            dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            dim.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            container.addSubview(dim)

            let spinner = UIActivityIndicatorView(style: .large)
            spinner.color = UIColor.white.withAlphaComponent(0.8)
            spinner.center = CGPoint(x: bounds.midX, y: bounds.height * 0.88)
            spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
            spinner.startAnimating()
            container.addSubview(spinner)

            container.alpha = 0
            addSubview(container)
            backdropView = container
            UIView.animate(withDuration: 0.3) { container.alpha = 1 }
        }
        backdropImageView?.image = image
        if let backdropView { bringSubviewToFront(backdropView) }
    }

    func hideBackdrop() {
        guard let container = backdropView else { return }
        backdropView = nil
        backdropImageView = nil
        UIView.animate(withDuration: 0.5, animations: { container.alpha = 0 }) { _ in
            container.removeFromSuperview()
        }
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
