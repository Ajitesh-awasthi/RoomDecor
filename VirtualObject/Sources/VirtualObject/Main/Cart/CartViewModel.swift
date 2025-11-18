import Foundation
import Combine

public final class CartViewModel: ObservableObject {
    @Published public var cartItems: [CartModel] = []
    private var cancellables = Set<AnyCancellable>()

    public init(items: [CartModel] = []) {
        self.cartItems = items
    }

    public func onAppear() {
        // If you do async loading or network-based persistence, do that here.
        // For now nothing required.
    }

    public var orderTotal: Double {
        cartItems.reduce(0.0) { $0 + ($1.price * Double($1.count)) }
    }

    public func stepperValueChanged(item: CartModel, count: Int) {
        guard let idx = cartItems.firstIndex(where: { $0.title == item.title }) else { return }
        cartItems[idx].count = max(0, count)
        // Optionally remove if count == 0
        if cartItems[idx].count == 0 {
            cartItems.remove(at: idx)
        }
    }

    // If you want to update items externally:
    public func replaceAll(items: [CartModel]) {
        cartItems = items
    }
}
