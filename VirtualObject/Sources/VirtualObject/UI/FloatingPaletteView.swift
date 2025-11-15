import UIKit
import ARKit

// delegate — keep internal visibility if your app requires it; change access if needed
protocol FloatingPaletteViewDelegate: AnyObject {
    func floatingPalette(_ palette: FloatingPaletteView, didSelect type: VirtualObjectType)
    func floatingPaletteDidToggle(_ palette: FloatingPaletteView, expanded: Bool)
}

final class FloatingPaletteView: UIView {

    // Public config
    weak var delegate: FloatingPaletteViewDelegate?
    private(set) var isExpanded: Bool = false

    // Data
    private var items: [VirtualObjectType] = []

    // UI
    private let headerButton = UIButton(type: .system)
    private let container = UIView()
    private let collectionView: UICollectionView

    // sizing
    private var collapsedWidth: CGFloat = 44
    private var expandedWidth: CGFloat = 220
    private var currentWidthConstraint: NSLayoutConstraint!

    // reuse id
    private let cellId = "FloatingPaletteCell"

    // MARK: - Init

    init(items: [VirtualObjectType]) {
        self.items = items

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)

        setupViews()
        configureCollectionView()
        applyCollapsed(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Setup

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        headerButton.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        // style self
        layer.cornerRadius = 12
        layer.masksToBounds = true
        backgroundColor = UIColor(white: 0.06, alpha: 0.85)

        // header button (chevron)
        headerButton.setTitle(nil, for: .normal)
        headerButton.tintColor = .white
        // use SF symbol chevron
        headerButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        headerButton.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        headerButton.accessibilityLabel = "Toggle palette"

        // container holds header + collection
        addSubview(container)
        container.addSubview(headerButton)
        container.addSubview(collectionView)

        // constraints: container to self
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // header placed at top-right vertically centered for collapsed look
        NSLayoutConstraint.activate([
            headerButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            headerButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            headerButton.widthAnchor.constraint(equalToConstant: collapsedWidth - 8),
            headerButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        // collection below header
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerButton.bottomAnchor, constant: 6),
            collectionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = true
        collectionView.register(FloatingPaletteCell.self, forCellWithReuseIdentifier: cellId)
        collectionView.dataSource = self
        collectionView.delegate = self
        // no drag gestures — the view is static; if any gesture recognizers exist in parent, ensure they don't intercept
        collectionView.isScrollEnabled = true
    }

    // MARK: - Public helpers

    /// Call after adding to parent. This method pins the palette to the right side with safe area insets.
    func attachToRight(of parent: UIView, topOffset: CGFloat = 120) {
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            trailingAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            topAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.topAnchor, constant: topOffset),
            heightAnchor.constraint(equalToConstant: 320)
        ])
        // width constraint: keep reference to animate expand/collapse
        currentWidthConstraint = widthAnchor.constraint(equalToConstant: collapsedWidth)
        currentWidthConstraint.isActive = true
    }

    func reloadItems(_ items: [VirtualObjectType]) {
        self.items = items
        collectionView.reloadData()
    }

    // MARK: - Toggle

    @objc private func toggleTapped() {
        setExpanded(!isExpanded, animated: true)
    }

    func setExpanded(_ expand: Bool, animated: Bool) {
        guard expand != isExpanded else { return }
        isExpanded = expand
        applyCollapsed(animated: animated)
        delegate?.floatingPaletteDidToggle(self, expanded: isExpanded)
    }

    private func applyCollapsed(animated: Bool) {
        // update chevron direction & width
        let chevronName = isExpanded ? "chevron.right" : "chevron.left"
        headerButton.setImage(UIImage(systemName: chevronName), for: .normal)

        // animate width change
        currentWidthConstraint?.constant = isExpanded ? expandedWidth : collapsedWidth
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut]) {
                self.superview?.layoutIfNeeded()
                // fade collection in/out
                self.collectionView.alpha = self.isExpanded ? 1.0 : 0.0
            }
        } else {
            self.collectionView.alpha = isExpanded ? 1.0 : 0.0
        }
    }
}

// MARK: - CollectionView DataSource & Delegate
extension FloatingPaletteView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellId, for: indexPath) as? FloatingPaletteCell else {
            return UICollectionViewCell()
        }

        let type = items[indexPath.item]

        // --- determine thumbnail image ---
        // Try multiple fallbacks:
        // 1) "<rawValue>_thumb" (common convention)
        // 2) rawValue
        // 3) a system placeholder
        var thumb: UIImage? = nil
        if let img = UIImage(named: "\(type.rawValue)_thumb", in: .module, with: nil) {
            thumb = img
        } else if let img = UIImage(named: type.rawValue, in: .module, with: nil) {
            thumb = img
        } else {
            thumb = UIImage(systemName: "cube.fill")
        }

        // --- determine display title ---
        // If you have a nicer displayName property on VirtualObjectType, change this line to use it.
        // Otherwise we generate a readable title from rawValue (replace underscores, capitalize)
        let raw = type.rawValue
        let displayTitle: String
        if let mirror = Mirror(reflecting: type).children.first(where: { $0.label == "displayName" }), let val = mirror.value as? String {
            displayTitle = val
        } else {
            // generic fallback: replace underscores/dashes and capitalize
            displayTitle = raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
        }

        cell.configure(title: displayTitle, image: thumb)
        return cell
    }


    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let type = items[indexPath.item]
        delegate?.floatingPalette(self, didSelect: type)
    }

    // layout: pick a reasonable cell size
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (expandedWidth - 24) // one column full width minus padding
        return CGSize(width: width, height: 84)
    }
}
