// Add to CartViewController.swift
import UIKit

public class CartViewController: UIViewController {
    private let items: [CartModel]

    // minimal initializer
    public init(items: [CartModel]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Cart (\(items.count))"
        // build UI using `items`
    }
}
