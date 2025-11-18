import UIKit
import Resolver
import CoreUi
import RoomScan
import SwiftUI
import VirtualObject
import SwiftUI
import RoomRedesign

class AppRouter:
    NSObject,
    VirtualObjectRouterProtocol,
    RoomScanRouterProtocol,
    SwitchModuleRouterProtocol{

    private let navigationController = UINavigationController()
    private let container: Resolver
    private lazy var coordinator = Coordinator()
    
    private lazy var initialViewController: UIViewController = {
        // Create the WelcomeView — provide actions that call AppRouter functions
        let welcomeView = WelcomeView(
            openVirtualAction: { [weak self] in
                self?.showVirtualObjectViewController(for: .armchair) // adjust if you need a default type
            },
            openRoomScanAction: { [weak self] in
                self?.showRoomScanViewController()
            }
        )
        // inject coordinator as environment object so WelcomeView can call presentCart, openRoomScan, etc.
        let root = welcomeView.environmentObject(coordinator)

        let host = UIHostingController(rootView: root)
        host.modalPresentationStyle = .fullScreen
        return host
    }()


    public init(container: Resolver) {
        self.container = container

        super.init()
        // wire coordinator back to this router so SwiftUI can call router actions
        coordinator.setAppRouter(self)
    }

    private var currentViewController: UIViewController? {
        navigationController.viewControllers.last
    }

    public func setStartScreen(in window: UIWindow?) {
        navigationController.setViewControllers([initialViewController], animated: false)

        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }
    
    func presentCart(with items: [CartModel], animated: Bool = true) {
        // Create the SwiftUI CartView (assumes CartView has initializer `init(items: [CartItem])`)
        let cartSwiftUIView = CartView()

        // Wrap it in a hosting controller and a nav controller for a close/back bar
        let host = UIHostingController(rootView: cartSwiftUIView)
        let nav = UINavigationController(rootViewController: host)
        nav.modalPresentationStyle = .automatic

        // Present from the current visible VC
        currentViewController?.present(nav, animated: animated, completion: nil)
    }


    func presentRedesignUI(for scanURL: URL) {
        print("\n🎯 === PRESENTING REDESIGN UI ===")
        print("📁 Scan URL: \(scanURL.path)")
        print("📁 Filename: \(scanURL.lastPathComponent)")
        print("📁 File exists? \(FileManager.default.fileExists(atPath: scanURL.path))")
        
        // Verify file exists before presenting
        guard FileManager.default.fileExists(atPath: scanURL.path) else {
            print("❌ ERROR: File doesn't exist, cannot present redesign UI")
            
            // List files in Documents to debug
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                print("\n📂 Files in Documents directory:")
                do {
                    let files = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
                    for file in files {
                        print("  - \(file.lastPathComponent)")
                    }
                } catch {
                    print("❌ Error listing files: \(error)")
                }
            }
            
            // Show error to user
            showError(for: .roomScanLoad)
            return
        }
        
        print("✅ File verified, creating ContentView...")
        
        let contentView = ContentView(scanURL: scanURL)
        let hostingController = UIHostingController(rootView: contentView)
        hostingController.modalPresentationStyle = .fullScreen
        
        print("✅ Presenting RoomRedesign UI...")
        self.navigationController.present(hostingController, animated: true) {
            print("✅ RoomRedesign UI presented successfully")
        }
    }

    public func showVirtualObjectViewController(for type: VirtualObjectType) {
        let virtualObjectViewController: VirtualObjectViewController = container.resolve(args: type)
        navigationController.pushViewController(virtualObjectViewController, animated: true)
    }

    func showRoomScanLandingViewController() {
        let roomScanLandingViewController: RoomScanLandingViewController = container.resolve(args: true)
        replaceLastViewController(with: roomScanLandingViewController)
    }

    public func showRoomScanViewController() {
        let roomScanViewController: RoomScanViewController = container.resolve()
        navigationController.pushViewController(roomScanViewController, animated: true)
    }

    public func presentSwitchModuleSheet() {
        let switchModuleViewController: SwitchModuleViewController = container.resolve()
        let modalViewController = ModalViewController(childViewController: switchModuleViewController)

        switchModuleViewController.onDismiss = {
            modalViewController.dismiss(animated: true)
        }

        navigationController.present(modalViewController, animated: true)
    }

    public func switchModule() {
//        if navigationController.viewControllers.last is RoomScanLandingViewController {
//            showVirtualObjectLandingViewController()
//        } else if navigationController.viewControllers.last is VirtualObjectLandingViewController {
//            showRoomScanLandingViewController()
//        }
    }

    public func presentShareSheet(for items: [URL]) {
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = currentViewController?.view
        currentViewController?.present(activityViewController, animated: true, completion: nil)
    }

    public func showWebView(url: URL?) {
        guard let url else { return }

        UIApplication.shared.open(url)
    }

    public func showErrorPopup(for type: RoomScanErrorType) {
        let errorType = ErrorType(from: type)
        showError(for: errorType)
    }

    public func showErrorPopup(for type: VirtualObjectErrorType) {
        let errorType = ErrorType(from: type)
        showError(for: errorType)
    }

    private func showError(for type: ErrorType) {
        let errorView = ErrorView()
        errorView.set(type: type)
        errorView.frame = UIScreen.main.bounds
        errorView.alpha = 0

        currentViewController?.view.addSubview(errorView)
        UIView.animate(withDuration: 0.3) {
            errorView.alpha = 1
        }

        errorView
            .buttonTapped
            .sink { [weak errorView] _ in
                guard let errorView else { return }

                UIView.animate(withDuration: 0.3) {
                    errorView.alpha = 0
                } completion: { _ in
                    errorView.removeFromSuperview()
                    errorView.disposables.removeAll()
                }
            }
            .store(in: &errorView.disposables)
    }

}

// MARK: - Helpers functions
extension AppRouter {

    func replaceLastViewController(with viewController: UIViewController, animated: Bool = true) {
        var viewControllers = navigationController.viewControllers

        guard !viewControllers.isEmpty else {
            navigationController.setViewControllers([viewController], animated: animated)
            return
        }

        viewControllers[viewControllers.count - 1] = viewController
        navigationController.setViewControllers(viewControllers, animated: animated)
    }

}

extension ErrorType {

    init(from type: RoomScanErrorType) {
        switch type {
        case .load:
            self = .roomScanLoad
        case .save:
            self = .roomScanSave
        case .session:
            self = .roomScanSession
        }
    }

    init(from type: VirtualObjectErrorType) {
        switch type {
        case .session:
            self = .virtualObjectSession
        case .loadObject:
            self = .virtualObjectLoadObject
        }
    }

}
