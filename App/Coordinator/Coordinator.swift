import Foundation
import SwiftUI
import RoomScan
import VirtualObject

/// Minimal coordinator to bridge SwiftUI -> AppRouter (UIKit)
public class Coordinator: ObservableObject {
    private weak var appRouter: AnyObject?

    public init(appRouter: AnyObject? = nil) {
        self.appRouter = appRouter
    }

    func setAppRouter(_ router: AnyObject?) {
        self.appRouter = router
    }

    // MARK: - Actions called from SwiftUI
    func openVirtualObject(for type: VirtualObjectType) {
        (appRouter as? VirtualObjectRouterProtocol)?.showVirtualObjectViewController(for: type)
    }

    func openRoomScan() {
        (appRouter as? RoomScanRouterProtocol)?.showRoomScanViewController()
    }

    func presentCart(items: [CartModel]) {
        (appRouter as? AppRouter)?.presentCart(with: items)
    }
}
