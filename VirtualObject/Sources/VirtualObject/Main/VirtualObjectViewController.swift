import ARKit
import Combine
import UIKit
import Core
import CoreUi

public class VirtualObjectViewController: UIViewController, UIGestureRecognizerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UISearchBarDelegate {

    let session = ARSession()
    let defaultPadding: CGFloat = 8
    let cornerRadius: CGFloat = 4
    let buttonHeight: CGFloat = 50
    let sightImageSize = CGSize(width: 100, height: 100)
    
    // Floating palette UI (right-side collapsible window)
    private var paletteButton: UIButton!
    private var paletteContainer: UIView!
    private var paletteScrollView: UIScrollView!
    private var paletteStack: UIStackView!
    private var paletteIsCollapsed: Bool = true
    
    private var remoteItems: [[String: Any]] = []
    // Cart UI + placed items tracking
    private var cartButton: UIButton!
    private var cartBadgeLabel: UILabel!
    private var cartTotalLabel: UILabel!
    private var placedItems: [[String: Any]] = []

    // Search/upload UI
    private var searchContainer: UIView?
    private var searchBar: UISearchBar?
    private var cameraButton: UIButton?
    // Last selected image that will be sent to the API
    private var selectedImage: UIImage?
    // add near other UI vars
    private var searchCameraButton: UIButton?


    // Palette sizing
    private let paletteCollapsedWidth: CGFloat = 56
    private let paletteExpandedWidth: CGFloat = 220
    private let paletteEdgePadding: CGFloat = 12
    // floating palette
    private var palette: FloatingPaletteView?
    private var selectedTypeForPlacement: VirtualObjectType? = nil

    // remember the user's current selection from the palette — used when user presses "Add"
    private var pendingSelectedType: VirtualObjectType?

    var sceneView: ARSCNView!
    var tap: UITapGestureRecognizer!
    var pan: UIPanGestureRecognizer!
    var longPress: UILongPressGestureRecognizer!           // for long-press + pan vertical control
    
    var sightImageView: UIImageView!
    var infoView: InfoView!
    var virtualObjectButton: UIButton!
    // add near other UI vars
    internal var backButton: UIButton!
    internal var paletteToggleButton: UIButton!

    
    // --- safety / highlight / gestures state ---
    private var originalScales: [ObjectIdentifier: SCNVector3] = [:]

    // Minimum allowed distance (meters) between camera and object
    private let minDistanceFromCamera: Float = 0.28   // ~28 cm, tune if needed
    private let highlightDistanceMargin: Float = 0.06 // reduce highlight when very close
    private let minPlaneClearance: Float = 0.01 // Minimum height above the detected floor plane (e.g., 1cm)

    // pan smoothing & offset
    private var panOffset: simd_float3?                // keeps the offset between node and hit point during pan

    // Last reliable hit position from raycast (world coords)
    private var lastValidHit: simd_float3?

    // Last reliable depth (meters)
    private var lastKnownDepth: Float?

    // Maximum allowed translation per frame (meters).
    private let maxMovePerFrame: Float = 0.2
    
    // screen-space pan state
    private var lastPanLocation: CGPoint?
    private var initialObjectDistance: Float?   // distance from camera to object when pan began

    // NEW screen-projection based state
    private var initialProjectedPoint: SCNVector3? // screen (x,y) + depth z from projectPoint at pan start
    private var panStartTranslation: CGPoint?      // translation value at .began to compute totals

    // vertical control flag toggled by long press
    private var longPressActive: Bool = false

    // tuning
    private let metersPerFullScreenPan: Float = 0.5 // kept for fallback / explanatory use


    // A threshold to detect unrealistic raycast jumps (meters) — treat very large jumps as noisy and ignore
    private let raycastJumpThreshold: Float = 1.5

    // If you want, enable debug prints
    private let enablePanDebugPrints = true

    // rotation gesture
    var rotationGesture: UIRotationGestureRecognizer!

    // smoothing factor default (tweakable) — lower = stronger smoothing
    private var panSmoothingFactor: Float = 0.18


    private var selectedNode: SCNNode?
    private var initialPanOffset: float4x4? // optional: keep offset between node and raycast hit if needed
    private let presenter: VirtualObjectPresenter!

    private var screenCenter: CGPoint?
    private var disposables = Set<AnyCancellable>()
    private var sessionConfig: ARConfiguration = ARWorldTrackingConfiguration()

    private var horizontalPlaneDetectedSubject = PassthroughSubject<Bool, Never>()

    var horizontalPlaneDetected: AnyPublisher<Bool, Never> {
        horizontalPlaneDetectedSubject
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }

    public init(presenter: VirtualObjectPresenter) {
        self.presenter = presenter

        super.init(nibName: nil, bundle: nil)

        configurePlaneDetection()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        print("DBG: viewDidLoad() - start")

        // 1) sceneView
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.session = session
        sceneView.delegate = self                           // <<< important!
        sceneView.scene = SCNScene()                        // ensure we have a scene
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)

        // pin sceneView to edges (so layout is correct)
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leftAnchor.constraint(equalTo: view.leftAnchor),
            sceneView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])

        // 2) add UI: BACK BUTTON (top-left) — replace existing backButton setup with this
        backButton = UIButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.accessibilityIdentifier = "backButton"

        // Use SF Symbol chevron for an arrow-style back button
        let backImage = UIImage(systemName: "chevron.left")

        if #available(iOS 15.0, *) {
            var cfg = UIButton.Configuration.plain()
            // set image and no text
            cfg.image = backImage
            cfg.imagePadding = 6
            cfg.baseForegroundColor = .white
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
            // keep compact sizing
            cfg.title = nil
            backButton.configuration = cfg
        } else {
            backButton.setImage(backImage, for: .normal)
            backButton.setTitle(nil, for: .normal)
            backButton.tintColor = .white
            backButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        }

        // circular-ish background like before
        backButton.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        backButton.layer.cornerRadius = 8
        backButton.layer.masksToBounds = true

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        view.addSubview(backButton)

        // place top-left with safe area insets
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: defaultPadding * 1.5),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: defaultPadding * 1.0),
            backButton.heightAnchor.constraint(equalToConstant: 36),
            backButton.widthAnchor.constraint(equalTo: backButton.heightAnchor, multiplier: 1.0) // square button
        ])


        // 3) placement button (bottom center)
        virtualObjectButton = UIButton(type: .system)
        virtualObjectButton.translatesAutoresizingMaskIntoConstraints = false
        virtualObjectButton.accessibilityIdentifier = "virtualObjectButton"
        if #available(iOS 15.0, *) {
            var cfg = UIButton.Configuration.filled()
            cfg.title = LocalizableStrings.addVirtualObject.localized
            cfg.baseBackgroundColor = .black
            cfg.baseForegroundColor = .white
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            virtualObjectButton.configuration = cfg
        } else {
            virtualObjectButton.setTitle(LocalizableStrings.addVirtualObject.localized, for: .normal)
            virtualObjectButton.setTitleColor(.white, for: .normal)
            virtualObjectButton.backgroundColor = .black
            virtualObjectButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        }
        virtualObjectButton.layer.cornerRadius = cornerRadius
        virtualObjectButton.isEnabled = false
        view.addSubview(virtualObjectButton)

        NSLayoutConstraint.activate([
            virtualObjectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            virtualObjectButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -defaultPadding * 2),
            virtualObjectButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            virtualObjectButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])

        // 4) infoView and sightImageView
        infoView = InfoView(frame: .zero)
        infoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoView)
        NSLayoutConstraint.activate([
            infoView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoView.bottomAnchor.constraint(equalTo: virtualObjectButton.topAnchor, constant: -defaultPadding),
            infoView.widthAnchor.constraint(equalToConstant: 220),
            infoView.heightAnchor.constraint(equalToConstant: 44)
        ])

        sightImageView = UIImageView(frame: .zero)
        sightImageView.translatesAutoresizingMaskIntoConstraints = false
        sightImageView.contentMode = .scaleAspectFit
        sightImageView.isUserInteractionEnabled = false
        sightImageView.image = UIImage(systemName: "plus")
        view.addSubview(sightImageView)
        NSLayoutConstraint.activate([
            sightImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sightImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sightImageView.widthAnchor.constraint(equalToConstant: sightImageSize.width),
            sightImageView.heightAnchor.constraint(equalToConstant: sightImageSize.height)
        ])

        // 5) gestures
        tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tap)

        pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2 // allow two-finger pan for vertical control
        pan.minimumNumberOfTouches = 1
        sceneView.addGestureRecognizer(pan)
        
        longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        longPress.allowableMovement = 20
        sceneView.addGestureRecognizer(longPress)

        tap.delegate = self
        pan.delegate = self
        longPress.delegate = self

        rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotationGesture.delegate = self
        sceneView.addGestureRecognizer(rotationGesture)

        // 6) ensure sensible screenCenter
        if screenCenter == nil {
            screenCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }

        // 7) binding & debug
        bindViews()
        setupFloatingPalette()
        createSearchUI()
        styleSearchUI()
        defineSearchLayout()
        setupCartUI()

        // Make sure UI is above the AR view (very important — ARSCNView tends to cover everything visually)
        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(virtualObjectButton)
        view.bringSubviewToFront(infoView)
        view.bringSubviewToFront(sightImageView)

        // Force layout and print debug frames
        view.setNeedsLayout()
        view.layoutIfNeeded()

        print("DBG: viewDidLoad() - subviews count = \(view.subviews.count)")
        print("DBG: viewDidLoad() - sceneView.frame = \(sceneView.frame)")
        print("DBG: viewDidLoad() - backButton.frame = \(backButton.frame) hidden=\(backButton.isHidden) alpha=\(backButton.alpha)")
        print("DBG: viewDidLoad() - virtualObjectButton.frame = \(virtualObjectButton.frame) hidden=\(virtualObjectButton.isHidden) alpha=\(virtualObjectButton.alpha)")
        print("DBG: viewDidLoad() - infoView.frame = \(infoView.frame)")
        print("DBG: viewDidLoad() - sightImageView.frame = \(sightImageView.frame)")
        print("DBG: viewDidLoad() - gesture recognizers on sceneView = \(sceneView.gestureRecognizers?.count ?? 0)")
        print("DBG: viewDidLoad() - tap.enabled=\(tap.isEnabled), pan.enabled=\(pan.isEnabled), longPress.enabled=\(longPress.isEnabled)")

        print("DBG: viewDidLoad() - end")
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        screenCenter = view.bounds.mid
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.isHidden = false
    }

    // Ensure AR session is running when the view becomes visible.
    // This helps in cases where we paused it before presenting the picker.
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIApplication.shared.isIdleTimerDisabled = true

        // Ensure session is running (re-run config if necessary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self = self else { return }
            if let worldConfig = self.sessionConfig as? ARWorldTrackingConfiguration {
                self.session.run(worldConfig, options: [])
                if self.enablePanDebugPrints { print("AR: session.run called in viewDidAppear to ensure camera resumed") }
            } else {
                if self.enablePanDebugPrints { print("AR: no ARWorldTrackingConfiguration available to run") }
            }
        }
    }


    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        session.pause()
    }

    private func configurePlaneDetection() {
        guard let worldSessionConfig = sessionConfig as? ARWorldTrackingConfiguration else {
            presenter.showErrorPopup(for: .session)
            return
        }

        worldSessionConfig.planeDetection = .horizontal
        session.run(worldSessionConfig, options: [.resetTracking, .removeExistingAnchors])
    }

    private func bindViews() {
        // Placement button: use selectedTypeForPlacement if set, otherwise fall back to presenter default
        virtualObjectButton
            .throttledTap()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // Decide which type to place: preference to selectedTypeForPlacement (set by palette tap)
                if let selected = self.selectedTypeForPlacement {
                    if self.enablePanDebugPrints { print("DBG: placing selected type = \(selected)") }
                    self.presenter.addVirtualObject(ofType: selected, screenCenter: self.screenCenter, sceneView: self.sceneView)
                } else {
                    if self.enablePanDebugPrints { print("DBG: placing presenter's default type (no palette selection)") }
                    self.presenter.addVirtualObject(screenCenter: self.screenCenter, sceneView: self.sceneView)
                }
            }
            .store(in: &disposables)
        
        // Plane detection publisher (unchanged behaviour, kept here)
        horizontalPlaneDetected
            .sink { [weak self] isPlaneDetected in
                guard let self = self else { return }
                
                UIView.animate(withDuration: 0.2) {
                    self.virtualObjectButton.isEnabled = isPlaneDetected
                    self.virtualObjectButton.layer.opacity = isPlaneDetected ? 1 : 0.2
                    self.infoView.layer.opacity = isPlaneDetected ? 0 : 1
                }
            }
            .store(in: &disposables)
    }
    
    // Creates the search container, search bar and camera/upload button.
    // Call this once (for example at the end of viewDidLoad after backButton & palette are created).
    func createSearchUI() {
        // remove existing if re-created accidentally
        if let existing = view.viewWithTag(0xDEADBEEF) {
            existing.removeFromSuperview()
        }

        // container to hold search bar + camera button
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        container.tag = 0xDEADBEEF
        view.addSubview(container)

        // search bar
        let sb = UISearchBar(frame: .zero)
        sb.translatesAutoresizingMaskIntoConstraints = false
        sb.placeholder = "Search objects or upload an image"
        sb.searchBarStyle = .minimal
        sb.returnKeyType = .search
        sb.autocapitalizationType = .none
        sb.isTranslucent = true
        if #available(iOS 13.0, *) {
            // make the text field readable over AR; light translucent background
            sb.searchTextField.backgroundColor = UIColor(white: 1.0, alpha: 0.9)
            sb.searchTextField.textColor = .label
        } else {
            sb.backgroundImage = UIImage() // minimize background on older iOS
        }

        // camera/upload button
        let cameraButton = UIButton(type: .system)
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        cameraButton.accessibilityIdentifier = "searchCameraButton"
        if #available(iOS 13.0, *) {
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            cameraButton.setImage(UIImage(systemName: "camera.fill", withConfiguration: cfg), for: .normal)
        } else {
            cameraButton.setTitle("📷", for: .normal)
        }
        cameraButton.tintColor = .label
        cameraButton.backgroundColor = UIColor(white: 0.0, alpha: 0.35)
        cameraButton.layer.cornerRadius = 6
        cameraButton.clipsToBounds = true
        cameraButton.addTarget(self, action: #selector(searchCameraTapped(_:)), for: .touchUpInside)

        container.addSubview(sb)
        container.addSubview(cameraButton)

        // Constraints:
        // Fixed height, centerX, and minimum width so it doesn't collapse to a pill.
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: defaultPadding),
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.heightAnchor.constraint(equalToConstant: 40),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 240) // ensure visible wide pill
        ])

        // Internal layout
        NSLayoutConstraint.activate([
            sb.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sb.topAnchor.constraint(equalTo: container.topAnchor),
            sb.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            cameraButton.leadingAnchor.constraint(equalTo: sb.trailingAnchor, constant: 8),
            cameraButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            cameraButton.centerYAnchor.constraint(equalTo: sb.centerYAnchor),
            cameraButton.widthAnchor.constraint(equalToConstant: 40),
            cameraButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        // Keep the search container within the gap between back and palette buttons if they exist:
        // leading >= backButton.trailing + padding OR leading >= safe area leading
        if let back = self.backButton, back.superview != nil {
            let lead = container.leadingAnchor.constraint(greaterThanOrEqualTo: back.trailingAnchor, constant: defaultPadding)
            lead.priority = .required
            lead.isActive = true
        } else {
            let lead = container.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: defaultPadding * 2)
            lead.priority = .required
            lead.isActive = true
        }

        // trailing <= paletteToggleButton.leading - padding OR safe area trailing
        if let pbtn = (self.paletteToggleButton ?? self.paletteButton), pbtn.superview != nil {
            let trail = container.trailingAnchor.constraint(lessThanOrEqualTo: pbtn.leadingAnchor, constant: -defaultPadding)
            trail.priority = .required
            trail.isActive = true
        } else {
            let trail = container.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -defaultPadding * 2)
            trail.priority = .required
            trail.isActive = true
        }

        // Make sure the search bar is flexible and camera button resists shrinking
        sb.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sb.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        cameraButton.setContentHuggingPriority(.required, for: .horizontal)
        cameraButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Store references (so style/other methods can access)
        self.searchBar = sb
        self.searchCameraButton = cameraButton

        // Bring above AR content
        view.bringSubviewToFront(container)
        view.bringSubviewToFront(backButton)
        if let p = paletteToggleButton { view.bringSubviewToFront(p) }
        if let p2 = paletteButton { view.bringSubviewToFront(p2) }

        if enablePanDebugPrints {
            print("DBG: createSearchUI() - container added, initial frame (may be zero until layout): \(container.frame)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                print("DBG: createSearchUI() - frames after layout -> container:\(container.frame) sb:\(sb.frame) camera:\(cameraButton.frame)")
            }
        }
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // dismiss keyboard immediately
        searchBar.resignFirstResponder()

        let query = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            if enablePanDebugPrints { print("SEARCH: empty query — ignoring") }
            return
        }

        if enablePanDebugPrints { print("SEARCH: user searched text -> '\(query)'") }

        // Show loader
        showLoading(true, message: "Searching...")

        Task { @MainActor in
            let macIP = self.getMacIP()
            guard let data = await self.callSearchAPI(macIP: macIP, prompt: query) else {
                // hide loader and show error
                self.showLoading(false, message: nil)
                self.infoView.set(title: "Search failed")
                return
            }

            // Parse the expected JSON array into dictionaries
            var items: [[String: Any]] = []
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let arr = json as? [[String: Any]] {
                    items = arr
                } else {
                    if enablePanDebugPrints { print("SEARCH: response not in expected array format") }
                }
            } catch {
                if enablePanDebugPrints { print("SEARCH: JSON parse error -> \(error.localizedDescription)") }
            }

            // If no items returned, inform user
            if items.isEmpty {
                self.showLoading(false, message: nil)
                self.infoView.set(title: "No results")
                return
            }

            // Ensure palette exists and expand it before populating
            if self.paletteContainer == nil {
                self.setupFloatingPalette()
            }
            self.setPaletteCollapsed(false, animated: true)

            // Populate palette UI with parsed items
            self.populatePaletteItems(with: items)

            // hide loader and update info
            self.showLoading(false, message: nil)
            self.infoView.set(title: "Found \(items.count) items")
        }
    }


    
    // Show an action sheet letting the user pick Camera or Photo Library
    @objc func searchCameraTapped(_ sender: Any?) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Take Photo", style: .default, handler: { [weak self] _ in
            self?.presentImagePicker(source: .camera)
        }))
        alert.addAction(UIAlertAction(title: "Choose from Library", style: .default, handler: { [weak self] _ in
            self?.presentImagePicker(source: .photoLibrary)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        // iPad popover anchor
        if let pop = alert.popoverPresentationController {
            pop.sourceView = self.view
            // anchor near top-center (where search bar is)
            pop.sourceRect = CGRect(x: self.view.bounds.midX, y: 44, width: 1, height: 1)
            pop.permittedArrowDirections = .any
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.present(alert, animated: true)
        }
    }

    // Configure the UISearchBar delegate and appearance. Ensure class conforms to UISearchBarDelegate.
    func styleSearchUI() {
        guard let sb = self.searchBar else {
            if enablePanDebugPrints { print("DBG: styleSearchUI() - searchBar is nil") }
            return
        }

        sb.delegate = self

        // Allow keyboard return to trigger search
        sb.searchTextField.clearButtonMode = .whileEditing
        sb.enablesReturnKeyAutomatically = false

        // Slight shadow for legibility when over AR content
        sb.layer.shadowColor = UIColor.black.cgColor
        sb.layer.shadowOpacity = 0.12
        sb.layer.shadowOffset = CGSize(width: 0, height: 1)
        sb.layer.shadowRadius = 2

        // If you want rounded pill look:
        sb.layer.cornerRadius = 10
        sb.clipsToBounds = true

        // Make sure camera/upload button is touchable and visible
        self.searchCameraButton?.isHidden = false
        self.searchCameraButton?.alpha = 1.0

        if enablePanDebugPrints {
            print("DBG: styleSearchUI() - applied styles to searchBar and cameraButton")
        }
    }
    
    // If you split layout into separate steps, call this after createSearchUI() and styleSearchUI().
    // This ensures layout constraints are updated and the search container doesn't overlap the corner buttons.
    func defineSearchLayout() {
        guard let container = view.viewWithTag(0xDEADBEEF) else {
            if enablePanDebugPrints { print("DBG: defineSearchLayout() - container missing") }
            return
        }

        // Force a layout pass and then make small adjustments if needed
        view.setNeedsLayout()
        view.layoutIfNeeded()

        // If the container is too wide and collides with corner buttons, reduce its width to fit between them.
        var leftEdge: CGFloat = view.safeAreaInsets.left + defaultPadding * 2
        var rightEdge: CGFloat = view.bounds.width - (view.safeAreaInsets.right + defaultPadding * 2)

        if let back = backButton, back.superview != nil {
            leftEdge = max(leftEdge, back.frame.maxX + defaultPadding)
        }
        if let pbtn = (paletteToggleButton ?? paletteButton), pbtn.superview != nil {
            rightEdge = min(rightEdge, pbtn.frame.minX - defaultPadding)
        }

        let maxAllowedWidth = max(160, rightEdge - leftEdge)
        // find width constraint we added earlier and update it if necessary
        if let w = container.constraints.first(where: { $0.firstAttribute == .width && $0.relation == .greaterThanOrEqual }) {
            w.constant = min(w.constant, maxAllowedWidth)
        } else {
            // set an upper bound so it doesn't overflow
            container.widthAnchor.constraint(lessThanOrEqualToConstant: maxAllowedWidth).isActive = true
        }

        // final bring to front
        view.bringSubviewToFront(container)
        view.bringSubviewToFront(backButton)
        if let p = paletteToggleButton { view.bringSubviewToFront(p) }
        if let p2 = paletteButton { view.bringSubviewToFront(p2) }

        if enablePanDebugPrints {
            print("DBG: defineSearchLayout() - container.frame = \(container.frame) maxAllowedWidth=\(maxAllowedWidth)")
        }
    }

    @objc private func showImageOptions(_ sender: Any?) {
        let ac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            ac.addAction(UIAlertAction(title: NSLocalizedString("Take Photo", comment: ""), style: .default, handler: { [weak self] _ in
                self?.presentImagePicker(source: .camera)
            }))
        }

        ac.addAction(UIAlertAction(title: NSLocalizedString("Choose from Library", comment: ""), style: .default, handler: { [weak self] _ in
            self?.presentImagePicker(source: .photoLibrary)
        }))

        ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))

        // iPad: anchor to camera button or search container
        if let pop = ac.popoverPresentationController, let cam = self.cameraButton {
            pop.sourceView = cam
            pop.sourceRect = cam.bounds
            pop.permittedArrowDirections = .any
        }

        DispatchQueue.main.async {
            self.present(ac, animated: true)
        }
    }
    
    // Updates: pause ARSession before presenting; present on main thread; set delegates properly.
    private func presentImagePicker(source: UIImagePickerController.SourceType) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard UIImagePickerController.isSourceTypeAvailable(source) else {
                let alert = UIAlertController(title: "Unavailable", message: source == .camera ? "Camera not available" : "Photo library not available", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
                return
            }

            // Pause AR session to free camera resources (prevents conflicts)
            self.session.pause()
            if self.enablePanDebugPrints { print("IMAGE: AR session paused before presenting picker") }

            let picker = UIImagePickerController()
            picker.sourceType = source
            picker.delegate = self
            picker.modalPresentationStyle = .fullScreen
            picker.allowsEditing = false

            self.present(picker, animated: true)
        }
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        // Always dismiss on main thread
        DispatchQueue.main.async {
            picker.dismiss(animated: true, completion: nil)
            if self.enablePanDebugPrints { print("IMAGE: user cancelled image picker") }
        }
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        // Extract image
        var chosenImage: UIImage?
        if let edited = info[.editedImage] as? UIImage { chosenImage = edited }
        else if let original = info[.originalImage] as? UIImage { chosenImage = original }

        // Dismiss first to avoid UI freeze/hang. Then process off main thread.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            picker.dismiss(animated: true) {
                if self.enablePanDebugPrints { print("IMAGE: picker dismissed, image != nil -> \(chosenImage != nil)") }

                // Resume AR session safely (small delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if let config = self.sessionConfig as? ARWorldTrackingConfiguration {
                        self.session.run(config, options: [])
                    }
                }

                guard let image = chosenImage else {
                    if self.enablePanDebugPrints { print("IMAGE: no image to process") }
                    return
                }

                // Offload heavy processing and network to background queue
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }

                    // Downscale/encode to JPEG to reduce upload size
                    let maxSide: CGFloat = 1024
                    let processed: UIImage
                    if max(image.size.width, image.size.height) > maxSide {
                        let aspect = image.size.width / image.size.height
                        let newSize = aspect > 1 ? CGSize(width: maxSide, height: maxSide / aspect) : CGSize(width: maxSide * aspect, height: maxSide)
                        UIGraphicsBeginImageContextWithOptions(newSize, true, 0.8)
                        image.draw(in: CGRect(origin: .zero, size: newSize))
                        processed = UIGraphicsGetImageFromCurrentImageContext() ?? image
                        UIGraphicsEndImageContext()
                    } else {
                        processed = image
                    }

                    guard let jpegData = processed.jpegData(compressionQuality: 0.8) else {
                        DispatchQueue.main.async {
                            if self.enablePanDebugPrints { print("IMAGE: failed to encode JPEG") }
                            self.infoView.set(title: "Image encode failed")
                        }
                        return
                    }

                    // store selected image in case you need it later
                    self.selectedImage = processed

                    // Show uploading loader
                    DispatchQueue.main.async {
                        self.showLoading(true, message: "Uploading...")
                        self.infoView.set(title: "Uploading image...")
                    }

                    let macIP = self.getMacIP()

                    Task { @MainActor in
                        guard let data = await self.uploadImageToMacAPI(macIP: macIP, imageData: jpegData) else {
                            self.showLoading(false, message: nil)
                            self.infoView.set(title: "Upload failed")
                            if self.enablePanDebugPrints { print("IMAGE: upload returned nil") }
                            return
                        }

                        // parse JSON array
                        var items: [[String: Any]] = []
                        do {
                            let json = try JSONSerialization.jsonObject(with: data, options: [])
                            if let arr = json as? [[String: Any]] {
                                items = arr
                            } else {
                                if self.enablePanDebugPrints { print("IMAGE: upload response not an array") }
                            }
                        } catch {
                            if self.enablePanDebugPrints { print("IMAGE: parse error -> \(error.localizedDescription)") }
                        }

                        if items.isEmpty {
                            self.showLoading(false, message: nil)
                            self.infoView.set(title: "No items returned")
                            return
                        }

                        // Ensure palette exists and expand it
                        if self.paletteContainer == nil {
                            self.setupFloatingPalette()
                        }
                        self.setPaletteCollapsed(false, animated: true)

                        // Populate palette with returned items
                        self.populatePaletteItems(with: items)

                        // Hide loader and update UI
                        self.showLoading(false, message: nil)
                        self.infoView.set(title: "Found \(items.count) items")
                    }
                }
            }
        }
    }


    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let node = selectedNode else {
            return
        }

        switch gesture.state {
        case .began:
            break

        case .changed:
            let rotation = Float(gesture.rotation)
            node.eulerAngles.y -= rotation
            gesture.rotation = 0

        default:
            break
        }
    }

    // Tap -> select a node under the tap
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: sceneView)

        // First, check SceneKit hit test for the delete badge specifically
        let options: [SCNHitTestOption: Any] = [.boundingBoxOnly: false, .firstFoundOnly: true, .searchMode: SCNHitTestSearchMode.all.rawValue]
        let hits = sceneView.hitTest(location, options: options)

        if let hit = hits.first {
            // If user tapped the delete badge or its geometry, remove the parent model
            var node = hit.node
            // walk upwards until we find either the badge or top-level model with a UUID name
            while node.parent != sceneView.scene.rootNode && node.parent != nil && node.name != "deleteBadge" {
                node = node.parent!
            }

            // tapped badge
            if node.name == "deleteBadge" || hit.node.name == "deleteBadge" {
                // The badge's parent should be the model node (we attached badge as child)
                let modelNode = node.parent ?? hit.node.parent
                if let toRemove = modelNode {
                    print("PAN: delete badge tapped — removing model node named \(toRemove.name ?? "<unknown>")")
                    // request presenter to remove and cleanup
                    presenter.removeVirtualObject(node: toRemove)
                } else {
                    print("PAN: delete badge tapped but parent model not found")
                }
                return
            }

            // not a badge -> treat as regular selection
            var pickNode = hit.node
            while pickNode.parent != sceneView.scene.rootNode && pickNode.parent != nil {
                pickNode = pickNode.parent!
            }
            selectedNode = pickNode
            highlight(node: pickNode, highlight: true)
            return
        }

        // If not SCN hit, maybe tap on empty space -> deselect
        if let prev = selectedNode {
            highlight(node: prev, highlight: false)
            selectedNode = nil
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        // Only act once when the gesture begins
        guard gesture.state == .began else { return }

        func dbg(_ msg: String) { if enablePanDebugPrints { print("PAN: \(msg)") } }

        let location = gesture.location(in: sceneView)
        dbg("longPress began at \(location)")

        // Hit-test SceneKit nodes first (gives the precise node tapped)
        let options: [SCNHitTestOption: Any] = [
            .boundingBoxOnly: false,
            .firstFoundOnly: true,
            .searchMode: SCNHitTestSearchMode.all.rawValue
        ]
        let hits = sceneView.hitTest(location, options: options)

        // If user long-pressed on a badge or model, pick the correct top-level model node
        var modelNode: SCNNode? = nil
        if let hit = hits.first {
            var node = hit.node
            // Walk up until we reach a top-level model node (child of scene root) OR find a named model marker
            while node.parent != sceneView.scene.rootNode && node.parent != nil {
                // if we attached a delete badge named "deleteBadge", allow it
                if node.name == "deleteBadge" { break }
                node = node.parent!
            }
            // If this node is the badge, use its parent as the model; otherwise use the top-level node
            if node.name == "deleteBadge" {
                modelNode = node.parent
            } else {
                // consider node as the model node if it's a direct child of root OR has an identifying name
                modelNode = node
            }
        }

        guard let nodeToRemove = modelNode else {
            dbg("longPress: no model under touch")
            return
        }

        // Select/highlight it for visual feedback
        selectedNode = nodeToRemove
        highlight(node: nodeToRemove, highlight: true)

        // Provide light haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Build confirmation alert
        let alert = UIAlertController(title: nil, message: "Remove this item?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive, handler: { [weak self] _ in
            guard let self = self else { return }
            dbg("user confirmed remove of node \(nodeToRemove.name ?? "<unnamed>")")

            // Ask presenter to do any cleanup / bookkeeping
            self.presenter.removeVirtualObject(node: nodeToRemove)

            // Remove from scene safely on main thread
            DispatchQueue.main.async {
                nodeToRemove.removeFromParentNode()
                // clear selection and UI
                self.highlight(node: nodeToRemove, highlight: false)
                if self.selectedNode === nodeToRemove { self.selectedNode = nil }
                dbg("node removed from scene")
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { [weak self] _ in
            guard let self = self else { return }
            // restore highlight state (or clear)
            if let sel = self.selectedNode, sel === nodeToRemove {
                self.highlight(node: sel, highlight: false)
                self.selectedNode = nil
            }
            dbg("user canceled remove")
        }))

        // For iPad: anchor the popover to the touched point / view
        if let popover = alert.popoverPresentationController, let sv = sceneView {
            popover.sourceView = sv
            popover.sourceRect = CGRect(origin: location, size: CGSize(width: 1, height: 1))
            popover.permittedArrowDirections = .any
        }

        // Present the alert on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.presentedViewController == nil {
                self.present(alert, animated: true)
            } else {
                dbg("longPress: another controller already presented; skipping alert")
            }
        }
    }

    private func cameraWorldPosition() -> simd_float3? {
        guard let t = sceneView.pointOfView?.simdWorldTransform else { return nil }
        return simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    private func highlight(node: SCNNode, highlight: Bool) {
        let baseFactor: Float = 1.05
        let id = ObjectIdentifier(node)

        if highlight {
            if originalScales[id] == nil {
                originalScales[id] = node.scale
            }
            let original = originalScales[id] ?? node.scale

            var factor = baseFactor
            if let camPos = cameraWorldPosition() {
                let nodePos = node.simdWorldPosition
                let dist = simd_length(nodePos - camPos)
                if dist <= (minDistanceFromCamera + highlightDistanceMargin) {
                    let t = max(0, min(1, (dist - minDistanceFromCamera) / highlightDistanceMargin))
                    factor = 1.0 + (baseFactor - 1.0) * t
                }
            }

            let target = SCNVector3(original.x * factor, original.y * factor, original.z * factor)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.12
            node.scale = target
            SCNTransaction.commit()

        } else {
            if let original = originalScales[id] {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.12
                node.scale = original
                SCNTransaction.commit()
                originalScales.removeValue(forKey: id)
            } else {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.12
                node.scale = SCNVector3(1, 1, 1)
                SCNTransaction.commit()
            }
        }
    }
    
    private func worldPosition(from transform: simd_float4x4) -> simd_float3 {
        let col = transform.columns.3
        return simd_float3(col.x, col.y, col.z)
    }
    
    private func cameraForwardVector() -> simd_float3? {
        guard let transform = sceneView.pointOfView?.simdWorldTransform else { return nil }
        let zAxis = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        return simd_normalize(-zAxis)
    }


    // ----------------------------
    // FINAL handlePan: screen-projection/unproject approach
    // - Project node to screen at .began, keep same depth (z)
    // - On pan, unproject (screenPos + totalPan) at same z to world point
    // - Vertical movement only allowed for two-finger pan or long-press
    // - Per-frame max move + smoothing + plane clearance enforced
    // ----------------------------
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let node = selectedNode else { return }
        guard let frame = sceneView.session.currentFrame else { return }

        func dbg(_ msg: String) { if enablePanDebugPrints { print("PAN: \(msg)") } }

        let camPos = simd_make_float3(frame.camera.transform.columns.3)
        let nodePos = node.simdWorldPosition

        switch gesture.state {
        case .began:
            let location = gesture.location(in: sceneView)
            dbg("began at \(location)")
            
            // Project node to screen: we'll keep the same z (depth) for unproject later
            let projected = sceneView.projectPoint(SCNVector3(nodePos.x, nodePos.y, nodePos.z))
            initialProjectedPoint = projected
            panStartTranslation = gesture.translation(in: sceneView)
            lastKnownDepth = initialObjectDistance // preserve if set (optional)
            
            // ensure node as root child to avoid parent transforms
            if node.parent !== sceneView.scene.rootNode {
                let worldTransform = node.simdWorldTransform
                sceneView.scene.rootNode.addChildNode(node)
                node.simdWorldTransform = worldTransform
                dbg("reparented node to scene.rootNode to avoid parent transforms")
            }

            // compute depth along camera forward for fallback safety
            if let forward = cameraForwardVector() {
                let ray = node.simdWorldPosition - camPos
                var depthAlong = simd_dot(ray, forward)
                if depthAlong <= 0.001 { depthAlong = simd_length(ray) }
                initialObjectDistance = max(depthAlong, minDistanceFromCamera)
                dbg("computed initialObjectDistance = \(String(describing: initialObjectDistance))")
            }

        case .changed:
            guard let initialProj = initialProjectedPoint,
                  let panStart = panStartTranslation else {
                dbg("missing initial projection — skipping")
                return
            }

            // total translation since began (use totals so unproject is stable)
            let totalTrans = gesture.translation(in: sceneView)
            let totalDx = Float(totalTrans.x - panStart.x)
            let totalDy = Float(totalTrans.y - panStart.y)

            dbg("changed at \(gesture.location(in: sceneView)), total translation since began = (\(totalDx), \(totalDy))")

            // build new screen point (x,y moved by pan), keep z (depth) same as initial projection
            var newScreenX = initialProj.x + totalDx
            var newScreenY = initialProj.y + totalDy
            let depthZ = initialProj.z

            // If vertical movement is NOT allowed, fix newScreenY to initialProj.y so unproject won't change Y.
            let twoFingerPanActive = gesture.numberOfTouches >= 2
            let allowVertical = twoFingerPanActive || longPressActive
            if !allowVertical {
                newScreenY = initialProj.y
                dbg("vertical input ignored (need 2-finger pan or long-press to enable vertical movement)")
            } else {
                dbg("vertical input allowed (twoFinger=\(twoFingerPanActive), longPress=\(longPressActive))")
            }

            let screenPoint = SCNVector3(newScreenX, newScreenY, depthZ)

            // Convert back to world
            let worldPoint = sceneView.unprojectPoint(screenPoint)
            var target = simd_make_float3(worldPoint.x, worldPoint.y, worldPoint.z)

            // Safety: If unproject somehow produced a point behind camera (rare), fallback to camera-forward depth projection
            if let forward = cameraForwardVector() {
                let forwardDot = simd_dot(forward, target - camPos)
                if forwardDot < minDistanceFromCamera {
                    target = camPos + forward * max(minDistanceFromCamera, initialObjectDistance ?? minDistanceFromCamera)
                    dbg("unproject produced point behind camera — clamped to forward depth")
                }
            }

            // Find plane under current touch and enforce minimum clearance if available
            let touchPoint = gesture.location(in: sceneView)
            var planeY: Float? = nil
            if let query = sceneView.raycastQuery(from: touchPoint, allowing: .estimatedPlane, alignment: .horizontal) {
                let results = sceneView.session.raycast(query)
                if let first = results.first {
                    planeY = first.worldTransform.columns.3.y
                }
            }

            // clamp Y relative to current node Y to avoid big jumps per frame
            let maxVerticalChangePerFrame: Float = 0.25
            let currentY = nodePos.y
            target.y = max(min(target.y, currentY + maxVerticalChangePerFrame), currentY - maxVerticalChangePerFrame)

            if let floorY = planeY {
                let minAllowed = floorY + minPlaneClearance
                target.y = max(target.y, minAllowed)
                dbg("Plane found at Y=\(floorY). enforcing minAllowedY=\(minAllowed)")
            }

            // ensure per-frame translation limit
            let moveDelta = target - nodePos
            let moveDistance = simd_length(moveDelta)
            if moveDistance > maxMovePerFrame {
                target = nodePos + moveDelta / moveDistance * maxMovePerFrame
                dbg("clamped move to maxMovePerFrame -> distance now = \(simd_length(target - nodePos))")
            }

            dbg("target(after clamps) = \(target)")

            // smoothing
            let smoothing = panSmoothingFactor
            let smoothed = simd_mix(nodePos, target, simd_make_float3(smoothing, smoothing, smoothing))
            let delta = smoothed - nodePos
            dbg("applying smoothed target=\(smoothed), delta length=\(simd_length(delta))")

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.02
            node.simdWorldPosition = smoothed
            SCNTransaction.commit()

            lastValidHit = node.simdWorldPosition

        case .ended, .cancelled, .failed:
            dbg("ended/cancelled/failed")
            lastPanLocation = nil
            initialObjectDistance = nil
            initialProjectedPoint = nil
            panStartTranslation = nil
            longPressActive = false
            if let node = selectedNode {
                highlight(node: node, highlight: false)
                dbg("deselected node")
            }

        default:
            break
        }
    }
    
    private func setupFloatingPalette() {
        // Avoid duplicate creation
        if paletteButton != nil { return }

        // Create the small toggle button (collapsed appearance)
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityIdentifier = "paletteToggleButton"
        btn.tintColor = .white

        if #available(iOS 13.0, *) {
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            btn.setImage(UIImage(systemName: "chevron.down", withConfiguration: cfg), for: .normal)
        } else {
            btn.setTitle("v", for: .normal)
        }

        btn.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        btn.layer.cornerRadius = 8
        btn.layer.masksToBounds = true
        btn.addTarget(self, action: #selector(togglePalette(_:)), for: .touchUpInside)

        view.addSubview(btn)
        self.paletteButton = btn

        // Position the button at same vertical level as backButton (or safe area top)
        let topAnchorRef = (backButton != nil) ? backButton.topAnchor : view.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            btn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -defaultPadding * 1.5),
            btn.topAnchor.constraint(equalTo: topAnchorRef),
            btn.heightAnchor.constraint(equalToConstant: 36),
            btn.widthAnchor.constraint(equalTo: btn.heightAnchor, multiplier: 1.0)
        ])

        // Create palette container but keep it hidden initially (no visible strip)
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        container.layer.cornerRadius = 12
        container.clipsToBounds = true
        container.isHidden = true
        container.alpha = 0.0
        view.addSubview(container)
        self.paletteContainer = container

        // Position container to the LEFT of the button (so button remains tappable on top)
        // trailing -> button.leading - 8
        NSLayoutConstraint.activate([
            container.trailingAnchor.constraint(equalTo: btn.leadingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: topAnchorRef, constant: 0),
            container.heightAnchor.constraint(equalToConstant: 320),
            container.widthAnchor.constraint(equalToConstant: paletteExpandedWidth)
        ])

        // Add a blurred background inside container for readability when expanded
        let blurEffect: UIBlurEffect
        if #available(iOS 13.0, *) {
            blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        } else {
            blurEffect = UIBlurEffect(style: .extraLight)
        }
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 12
        blurView.clipsToBounds = true
        container.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Scroll + stack (transparent to let blur show)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.backgroundColor = .clear
        container.addSubview(scroll)
        self.paletteScrollView = scroll

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.distribution = .fill
        scroll.addSubview(stack)
        self.paletteStack = stack

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        // Populate items now (wrapper uses remoteItems)
        populatePaletteItems()

        // Collapsed logical state
        paletteIsCollapsed = true
        paletteScrollView?.alpha = 0.0
        paletteScrollView?.isUserInteractionEnabled = false

        // Ensure button stays above container
        view.bringSubviewToFront(container)
        view.bringSubviewToFront(btn)

        if enablePanDebugPrints { print("PAL: setupFloatingPalette -> created button + hidden container (no visible strip).") }
    }



    // 3) togglePalette - ensure container exists before toggling
    @objc private func togglePalette(_ sender: Any?) {
        // if container is nil, try to create it
        if paletteContainer == nil {
            setupFloatingPalette()
        }
        setPaletteCollapsed(!paletteIsCollapsed, animated: true)
    }



    // Build views for palette items based on your VirtualObjectCardView.
    // This assumes VirtualObjectType: CaseIterable and VirtualObjectType has `rawValue` or `displayName`.
    private func allTypes() -> [VirtualObjectType] {
        if let list = (VirtualObjectType.self as? (any CaseIterable.Type)) {
            // unsafe cast to CaseIterable - better if VirtualObjectType: CaseIterable in your code
            return (VirtualObjectType.allCases as? [VirtualObjectType]) ?? []
        }
        // fallback - if you have presenter-based list, call presenter API here
        return []
    }

    // wrapper so previous calls without args still work
    private func populatePaletteItems() {
        populatePaletteItems(with: self.remoteItems)
    }

    private func populatePaletteItems(with items: [[String: Any]]) {
        // Persist items for later mapping when user taps a palette row
        self.remoteItems = items

        // Ensure palette stack exists
        guard let stack = self.paletteStack, let scroll = self.paletteScrollView else {
            if enablePanDebugPrints { print("PAL: populatePaletteItems -> missing UI stack/scroll") }
            return
        }

        // Clear existing
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Build a card per returned item
        for (index, dict) in items.enumerated() {
            // Create or reuse your VirtualObjectCardView; if it doesn't match, create a generic card-like view
            let card = VirtualObjectCardView(frame: .zero)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.backgroundColor = UIColor.clear
            card.layer.cornerRadius = 8
            card.clipsToBounds = true

            // Use available fields safely
            let name = dict["itemName"] as? String ?? ""
            let price = dict["price"] as? NSNumber
            let priceUnit = dict["priceUnit"] as? String ?? ""
            let rating = dict["rating"] as? NSNumber
            let img2D = dict["imageLink2D"] as? String
            let length = dict["length"] as? NSNumber
            let width = dict["width"] as? NSNumber
            let height = dict["height"] as? NSNumber
            let dimUnit = dict["dimUnit"] as? String ?? ""

            // Configure title label (we will place it under rating)
            if let tLabel = card.titleLabel {
                tLabel.translatesAutoresizingMaskIntoConstraints = false
                tLabel.numberOfLines = 2
                tLabel.lineBreakMode = .byWordWrapping
                tLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
                tLabel.textColor = .white
                tLabel.text = name
            }

            // Reset image placeholder
            if let imgView = card.imageView {
                imgView.image = UIImage(systemName: "photo")
                imgView.contentMode = .scaleAspectFill
                imgView.clipsToBounds = true
                imgView.translatesAutoresizingMaskIntoConstraints = false
                imgView.layer.cornerRadius = 6
            }

            // Price label (right side)
            let priceLabel = UILabel()
            priceLabel.translatesAutoresizingMaskIntoConstraints = false
            priceLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            priceLabel.textAlignment = .right
            priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            priceLabel.setContentHuggingPriority(.required, for: .horizontal)
            if let p = price?.doubleValue {
                priceLabel.text = String(format: "%.0f %@", p, priceUnit)
            } else {
                priceLabel.text = "-"
            }

            // Rating label (below price)
            let ratingLabel = UILabel()
            ratingLabel.translatesAutoresizingMaskIntoConstraints = false
            ratingLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
            ratingLabel.textAlignment = .right
            ratingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            if let r = rating?.doubleValue {
                ratingLabel.text = String(format: "★ %.1f", r)
            } else {
                ratingLabel.text = "★ -"
            }

            // Size label below image — allow wrap and full text (no truncation)
            let sizeLabel = UILabel()
            sizeLabel.translatesAutoresizingMaskIntoConstraints = false
            sizeLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
            sizeLabel.textAlignment = .center
            sizeLabel.numberOfLines = 1
            sizeLabel.lineBreakMode = .byClipping
            if let l = length?.doubleValue, let w = width?.doubleValue, let h = height?.doubleValue {
                sizeLabel.text = String(format: "%.1f x %.1f x %.1f %@", l, w, h, dimUnit)
            } else {
                sizeLabel.text = ""
            }

            // Add subviews
            card.addSubview(priceLabel)
            card.addSubview(ratingLabel)
            card.addSubview(sizeLabel)
            if let imgView = card.imageView { card.addSubview(imgView) }
            if let tLabel = card.titleLabel { card.addSubview(tLabel) }

            // Layout accessory labels relative to card's contents.
            // Image on left fixed 64x64, size label below it; price & rating pinned to trailing
            if let imgView = card.imageView {
                NSLayoutConstraint.activate([
                    imgView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                    imgView.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                    imgView.widthAnchor.constraint(equalToConstant: 64),
                    imgView.heightAnchor.constraint(equalToConstant: 64)
                ])

                // Size label sits under the image, nudged slightly right (so it doesn't overlap with image edge)
                NSLayoutConstraint.activate([
                    sizeLabel.topAnchor.constraint(equalTo: imgView.bottomAnchor, constant: 6),
                    sizeLabel.leadingAnchor.constraint(equalTo: imgView.leadingAnchor, constant: 6),
                    sizeLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -8)
                ])
            } else {
                // fallback anchors if imageView not present
                NSLayoutConstraint.activate([
                    sizeLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                    sizeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                    sizeLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -8)
                ])
            }

            // Price & rating pinned to card's trailing
            NSLayoutConstraint.activate([
                priceLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
                priceLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
                priceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 110),

                ratingLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
                ratingLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 4),
                ratingLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 110)
            ])

            // Place title UNDER rating (as requested). Title aligns to the same trailing as price/rating,
            // and its leading is at least after the image so it doesn't overlap.
            if let tLabel = card.titleLabel {
                NSLayoutConstraint.activate([
                    tLabel.topAnchor.constraint(equalTo: ratingLabel.bottomAnchor, constant: 6),
                    tLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
                    tLabel.leadingAnchor.constraint(greaterThanOrEqualTo: (card.imageView?.trailingAnchor ?? card.leadingAnchor), constant: 12)
                ])
            }

            // Set fixed height for card so scroll works predictably (allowing additional sizeLabel height)
            card.heightAnchor.constraint(equalToConstant: 120).isActive = true

            // Add tap recognizer to place item on tap
            let tap = UITapGestureRecognizer(target: self, action: #selector(paletteItemTapped(_:)))
            card.addGestureRecognizer(tap)
            card.isUserInteractionEnabled = true
            card.tag = index // map to remoteItems

            // Add to stack
            stack.addArrangedSubview(card)

            // Load image2D asynchronously if URL present
            if let imgURLStr = img2D, let url = URL(string: imgURLStr) {
                Task.detached(priority: .utility) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            await MainActor.run {
                                card.imageView?.image = image
                                card.imageView?.contentMode = .scaleAspectFill
                            }
                        }
                    } catch {
                        if self.enablePanDebugPrints { print("PAL: failed to load image2D for item[\(index)] -> \(error.localizedDescription)") }
                    }
                }
            }
        }

        // Update scroll content layout after adding all cards
        scroll.setNeedsLayout()
        scroll.layoutIfNeeded()

        if enablePanDebugPrints {
            print("PAL: populatePaletteItems -> added \(items.count) items")
        }
    }

    private func showLoading(_ show: Bool, message: String?) {
        // Use a single activity indicator attached to the top-right (near palette button) or center if not available.
        let loaderTag = 0xDEAD_BEEF
        if show {
            // if already present, update
            if let existing = view.viewWithTag(loaderTag) as? UIActivityIndicatorView {
                existing.startAnimating()
                if let msg = message { self.infoView.set(title: msg) }
                return
            }

            let indicator = UIActivityIndicatorView(style: .large)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            indicator.tag = loaderTag
            indicator.startAnimating()
            indicator.hidesWhenStopped = true
            indicator.color = .white

            // a subtle dark blurred background circle to ensure visibility
            let bg = UIView()
            bg.translatesAutoresizingMaskIntoConstraints = false
            bg.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
            bg.layer.cornerRadius = 28
            bg.clipsToBounds = true
            bg.tag = loaderTag + 1

            bg.addSubview(indicator)
            view.addSubview(bg)

            // place near top-right under the palette button if present; otherwise center
            if let paletteBtn = paletteButton, paletteBtn.superview != nil {
                NSLayoutConstraint.activate([
                    bg.trailingAnchor.constraint(equalTo: paletteBtn.leadingAnchor, constant: -12),
                    bg.centerYAnchor.constraint(equalTo: paletteBtn.centerYAnchor),
                    bg.widthAnchor.constraint(equalToConstant: 56),
                    bg.heightAnchor.constraint(equalToConstant: 56),

                    indicator.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
                    indicator.centerYAnchor.constraint(equalTo: bg.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    bg.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    bg.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                    bg.widthAnchor.constraint(equalToConstant: 100),
                    bg.heightAnchor.constraint(equalToConstant: 100),

                    indicator.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
                    indicator.centerYAnchor.constraint(equalTo: bg.centerYAnchor)
                ])
            }

            if let msg = message { self.infoView.set(title: msg) }
        } else {
            // hide & remove
            if let existing = view.viewWithTag(loaderTag) as? UIActivityIndicatorView {
                existing.stopAnimating()
                existing.removeFromSuperview()
            }
            if let bg = view.viewWithTag(loaderTag + 1) {
                bg.removeFromSuperview()
            }
        }
    }


    private func setPaletteCollapsed(_ collapsed: Bool, animated: Bool) {
        // If already in requested state, do nothing
        if paletteIsCollapsed == collapsed {
            if enablePanDebugPrints { print("PAL: setPaletteCollapsed -> already \(collapsed ? "collapsed" : "expanded")") }
            return
        }

        paletteIsCollapsed = collapsed

        // Update button icon immediately
        if #available(iOS 13.0, *) {
            let symbolName = collapsed ? "chevron.down" : "chevron.up"
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            paletteButton?.setImage(UIImage(systemName: symbolName, withConfiguration: cfg), for: .normal)
        } else {
            paletteButton?.setTitle(collapsed ? "v" : "^", for: .normal)
        }

        guard let container = paletteContainer, let scroll = paletteScrollView else {
            if enablePanDebugPrints { print("PAL: setPaletteCollapsed - paletteContainer or paletteScrollView is nil; nothing to animate") }
            return
        }

        // If expanding: unhide first so alpha animation is visible.
        if !collapsed {
            container.isHidden = false
            scroll.isUserInteractionEnabled = true
            // ensure correct layering: container behind button
            view.bringSubviewToFront(container)
            view.bringSubviewToFront(paletteButton)
        }

        let animations = {
            container.alpha = collapsed ? 0.0 : 1.0
            scroll.alpha = collapsed ? 0.0 : 1.0
        }

        let completion: (Bool) -> Void = { _ in
            if collapsed {
                container.isHidden = true
                scroll.isUserInteractionEnabled = false
                if self.enablePanDebugPrints { print("PAL: collapsed -> container hidden") }
            } else {
                if self.enablePanDebugPrints { print("PAL: expanded -> container visible") }
            }
        }

        if animated {
            // Use UIView animation block
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut], animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }


    private func updatePaletteButtonIcon() {
        guard let btn = self.paletteButton else { return }
        let imageName = paletteIsCollapsed ? "chevron.down" : "chevron.up"
        if #available(iOS 13.0, *) {
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            let img = UIImage(systemName: imageName, withConfiguration: cfg)
            if #available(iOS 15.0, *) {
                if var conf = btn.configuration {
                    conf.image = img
                    btn.configuration = conf
                } else {
                    btn.setImage(img, for: .normal)
                }
            } else {
                btn.setImage(img, for: .normal)
            }
        } else {
            btn.setTitle(paletteIsCollapsed ? "v" : "^", for: .normal)
        }
    }


    @objc private func paletteItemTapped(_ gesture: UITapGestureRecognizer) {
        guard let card = gesture.view as? VirtualObjectCardView else {
            if enablePanDebugPrints { print("PAL: paletteItemTapped - tap not on card") }
            return
        }

        let idx = card.tag

        // If we have remoteItems (results from search/upload), prefer placing remote 3D model
        if idx >= 0 && idx < remoteItems.count {
            let dict = remoteItems[idx]
            if let remote3D = dict["imageLink3D"] as? String, let url = URL(string: remote3D) {
                if enablePanDebugPrints { print("PAL: paletteItemTapped -> downloading remote 3D for index \(idx) -> \(remote3D)") }
                // Show a small loader
                showLoading(true, message: "Loading model...")
                Task {
                    await placeRemoteModel(at: idx)
                }
                return
            }
        }

        // Fallback: previous behavior (local VirtualObjectType mapping)
        // Recompute types in the same order used by populatePaletteItems()
        let types: [VirtualObjectType]
        if let _ = (VirtualObjectType.self as? CaseIterable.Type) {
            types = (VirtualObjectType.allCases as? [VirtualObjectType]) ?? []
        } else {
            if let list = (presenter as? AnyObject)?.value(forKey: "availableTypes") as? [VirtualObjectType] {
                types = list
            } else {
                types = []
            }
        }

        guard card.tag >= 0 && card.tag < types.count else {
            if enablePanDebugPrints { print("PAL: paletteItemTapped - invalid index \(card.tag)") }
            return
        }

        let selectedType = types[card.tag]
        if enablePanDebugPrints { print("PAL: paletteItemTapped -> selected \(selectedType.rawValue) (index \(card.tag))") }

        // Save selection for the "Place Item" button to use later
        selectedTypeForPlacement = selectedType

        // Clear visual selection on all cards
        paletteStack.arrangedSubviews.forEach { sub in
            if let c = sub as? VirtualObjectCardView {
                c.layer.borderWidth = 0
                c.layer.borderColor = UIColor.clear.cgColor
                c.backgroundColor = UIColor(white: 1.0, alpha: 0.0)
            }
        }

        // Visually mark the selected card (simple highlight)
        card.layer.borderWidth = 2
        card.layer.borderColor = UIColor.systemBlue.cgColor
        card.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)

        // Collapse palette after selection for clarity (optional)
        setPaletteCollapsed(true, animated: true)
    }

    private func placeRemoteModel(at index: Int) async {
        guard index >= 0 && index < remoteItems.count else {
            await MainActor.run {
                self.showLoading(false, message: nil)
                self.infoView.set(title: "Invalid item")
            }
            return
        }

        let dict = remoteItems[index]
        guard let remote3D = dict["imageLink3D"] as? String, let url = URL(string: remote3D) else {
            await MainActor.run {
                self.showLoading(false, message: nil)
                self.infoView.set(title: "No 3D link")
            }
            return
        }

        // Download to temp file
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                await MainActor.run {
                    self.showLoading(false, message: nil)
                    self.infoView.set(title: "Model download failed: HTTP \(http.statusCode)")
                }
                return
            }
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            await MainActor.run {
                self.showLoading(false, message: nil)
                self.infoView.set(title: "Download error")
                if self.enablePanDebugPrints { print("PAL: failed to download 3D -> \(error.localizedDescription)") }
            }
            return
        }

        // Try to load the model using SceneKit's URL-based loader
        do {
            // Attempt to create a SCNScene directly from the file URL.
            // This works for many supported formats. If SceneKit can't parse it, it'll throw and we'll show an error.
            let scene = try SCNScene(url: tmpURL, options: nil)

            // Create a container node and attach all children from scene.rootNode
            let container = SCNNode()
            for child in scene.rootNode.childNodes {
                container.addChildNode(child)
            }

            // Simple bounding and scale normalization - optional small auto-scale
            let (minVec, maxVec) = container.boundingBox
            let size = SCNVector3(
                x: maxVec.x - minVec.x,
                y: maxVec.y - minVec.y,
                z: maxVec.z - minVec.z
            )
            let maxSide = max(size.x, max(size.y, size.z))
            if maxSide > 0 {
                // target ~0.5m largest dimension (tweak as required)
                let desired: Float = 0.5
                let scale = desired / maxSide
                container.scale = SCNVector3(scale, scale, scale)
            }

            // Place the model roughly 0.6m in front of the camera (screen center)
            var placementPosition = SCNVector3(0, 0, -0.6)
            if let pov = sceneView.pointOfView {
                // convert local forward point to world
                let local = SCNVector3(0, 0, -0.6)
                let worldPos = pov.convertPosition(local, to: sceneView.scene.rootNode)
                placementPosition = worldPos
                // align orientation with camera yaw
                container.eulerAngles.y = pov.eulerAngles.y
            }

            container.position = placementPosition

            // Add a unique name so selection / deletion logic can operate
            container.name = "remoteModel_\(UUID().uuidString)"

            // Add to scene on main thread
            await MainActor.run {
                self.sceneView.scene.rootNode.addChildNode(container)
                // set selection to the newly placed node and update UI
                self.selectedNode = container
                self.highlight(node: container, highlight: true)
                self.addPlacedItem(dict)
                self.showLoading(false, message: nil)
                self.infoView.set(title: dict["itemName"] as? String ?? "Model placed")
                if self.enablePanDebugPrints { print("PAL: placed remote model from \(remote3D)") }

                // Optionally collapse palette after placing
                self.setPaletteCollapsed(true, animated: true)
            }
        } catch {
            // If SceneKit couldn't load it, surface a clear error and log for debugging
            await MainActor.run {
                self.showLoading(false, message: nil)
                self.infoView.set(title: "Model load failed")
                if self.enablePanDebugPrints { print("PAL: SCNScene(url:) failed -> \(error.localizedDescription). File: \(tmpURL.path)") }
            }
        }
    }

    // Helper: very small mapping function — replace with your project's mapping
    private func virtualObjectType(forDisplayName name: String) -> VirtualObjectType? {
        // If VirtualObjectType is RawRepresentable by String:
        if let t = VirtualObjectType(rawValue: name) {
            return t
        }
        // Otherwise loop through allCases (if CaseIterable) and match description or rawValue
        if let all = VirtualObjectType.allCases as? [VirtualObjectType] {
            return all.first { (($0 as? CustomStringConvertible)?.description ?? "\($0)") == name || "\($0)" == name }
        }
        return nil
    }
    
    // add this exact method inside the VirtualObjectViewController class
    @MainActor
    func callSearchAPI(macIP: String, prompt: String) async -> Data? {
        // Build URL safely using URLComponents
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = macIP
        comps.port = 8093
        comps.path = "/prompt-search" // your search endpoint; replace if different

        guard let url = comps.url else {
            if enablePanDebugPrints { print("SEARCH: invalid URL for macIP=\(macIP) prompt=\(prompt)") }
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // JSON payload: { "request": "<prompt>" }
        let payload: [String: String] = ["request": prompt]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            if enablePanDebugPrints { print("SEARCH: failed to encode JSON payload -> \(error.localizedDescription)") }
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if enablePanDebugPrints { print("SEARCH: server returned HTTP \(http.statusCode)") }
                return nil
            }

            return data
        } catch {
            if enablePanDebugPrints { print("SEARCH: network error -> \(error.localizedDescription)") }
            return nil
        }
    }

    
    // add this exact method inside the VirtualObjectViewController class
    @objc func onSearchButtonTapped(_ sender: Any) {
        // Replace "192.168.1.10" with your Mac's LAN IP at runtime or read from a settings field.
        // If you already store macIP somewhere (e.g. a property), use that instead.
        let macIP = self.getMacIP() // <-- Change this to your Mac's IP when testing

        // If you have a UISearchBar property named `searchBar`, use it. Otherwise replace with your text source.
        let promptText: String
        if let sb = (self.value(forKey: "searchBar") as? UISearchBar) {
            promptText = sb.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            // fallback: try a stored property named `searchTextField` or default
            promptText = ""
        }

        guard !promptText.isEmpty else {
            // optional: show a toast / info view instead of silently returning
            print("Search: prompt empty — ignoring")
            return
        }

        // Show loading UI if you have one (e.g., infoView or ProgressView)
        DispatchQueue.main.async {
            self.infoView.set(title: "Searching...")
        }

        Task { @MainActor in
            let result = await callSearchAPI(macIP: macIP, prompt: promptText)

            // update UI with the server response
            // e.g., set info view text or a label you use for responses
            self.infoView.set(title: "Server: \(result)")

            // optional debug log
            if self.enablePanDebugPrints { print("SEARCH: result = \(result)") }
        }
    }
    
    @MainActor
    func uploadImageToMacAPI(macIP: String, imageData: Data) async -> Data? {
        // NOTE: change `/upload-image` to the endpoint your server expects for uploads.
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = macIP
        comps.port = 8093
        comps.path = "/upload-image"

        guard let url = comps.url else {
            if enablePanDebugPrints { print("UPLOAD: invalid URL for macIP=\(macIP)") }
            return nil
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()
        let filename = "photo.jpg"
        let mimetype = "image/jpeg"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimetype)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if enablePanDebugPrints { print("UPLOAD: server returned HTTP \(http.statusCode)") }
                return nil
            }

            return data
        } catch {
            if enablePanDebugPrints { print("UPLOAD: network error -> \(error.localizedDescription)") }
            return nil
        }
    }
    
    private func setupCartUI() {
        // Build a small cart button with badge and a price label under it
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityIdentifier = "cartButton"
        if #available(iOS 13.0, *) {
            let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            btn.setImage(UIImage(systemName: "cart.fill", withConfiguration: cfg), for: .normal)
        } else {
            btn.setTitle("Cart", for: .normal)
        }
        btn.tintColor = .white
        btn.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        btn.layer.cornerRadius = 8
        btn.layer.masksToBounds = true
        btn.addTarget(self, action: #selector(cartButtonTapped(_:)), for: .touchUpInside)

        view.addSubview(btn)
        self.cartButton = btn

        // Badge
        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        badge.textColor = .white
        badge.backgroundColor = .systemRed
        badge.textAlignment = .center
        badge.layer.cornerRadius = 10
        badge.clipsToBounds = true
        badge.isHidden = true // hidden when 0
        view.addSubview(badge)
        self.cartBadgeLabel = badge

        // Total price label
        let totalLbl = UILabel()
        totalLbl.translatesAutoresizingMaskIntoConstraints = false
        totalLbl.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        totalLbl.textColor = .white
        totalLbl.textAlignment = .center
        totalLbl.numberOfLines = 1
        totalLbl.text = "" // initially empty
        view.addSubview(totalLbl)
        self.cartTotalLabel = totalLbl

        // Positioning:
        // If palette button exists, place cart left to palette; otherwise top-right safe area
        if let paletteBtn = self.paletteButton, paletteBtn.superview != nil {
            NSLayoutConstraint.activate([
                btn.trailingAnchor.constraint(equalTo: paletteBtn.leadingAnchor, constant: -12),
                btn.topAnchor.constraint(equalTo: paletteBtn.topAnchor),
                btn.widthAnchor.constraint(equalToConstant: 44),
                btn.heightAnchor.constraint(equalToConstant: 44)
            ])
        } else {
            NSLayoutConstraint.activate([
                btn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -defaultPadding * 1.5),
                btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: defaultPadding * 1.0),
                btn.widthAnchor.constraint(equalToConstant: 44),
                btn.heightAnchor.constraint(equalToConstant: 44)
            ])
        }

        // Badge anchored top-right of button
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: btn.trailingAnchor, constant: -6),
            badge.centerYAnchor.constraint(equalTo: btn.topAnchor, constant: 6),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20)
        ])

        // Total label below the button (small)
        NSLayoutConstraint.activate([
            totalLbl.topAnchor.constraint(equalTo: btn.bottomAnchor, constant: 6),
            totalLbl.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            totalLbl.widthAnchor.constraint(lessThanOrEqualToConstant: 160)
        ])

        // Initial update
        updateCartUI()
    }
    
    @objc private func cartButtonTapped(_ sender: Any?) {
        // Present a simple list or summary — for now, just print debug and show infoView.
        if enablePanDebugPrints { print("CART: tapped, items=\(placedItems.count)") }
        if placedItems.isEmpty {
            infoView.set(title: "Cart is empty")
        } else {
            // Show summary: count + total
            let totalText = cartTotalLabel.text ?? ""
            infoView.set(title: "Items: \(placedItems.count) • \(totalText)")
        }
    }

    private func updateCartUI() {
        // Compute total price and unit (use first non-empty unit found)
        var total: Double = 0
        var unit: String? = nil
        for item in placedItems {
            if let p = item["price"] as? NSNumber {
                total += p.doubleValue
            } else if let p = item["price"] as? Double {
                total += p
            }
            if unit == nil {
                if let u = item["priceUnit"] as? String, !u.isEmpty {
                    unit = u
                }
            }
        }

        // Update badge
        if placedItems.isEmpty {
            cartBadgeLabel.isHidden = true
        } else {
            cartBadgeLabel.isHidden = false
            cartBadgeLabel.text = "\(placedItems.count)"
        }

        // Update total label (rounded to 2 decimals if needed; prefer integer when no fraction)
        if placedItems.isEmpty {
            cartTotalLabel.text = ""
        } else {
            let rounded = (total.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", total) : String(format: "%.2f", total)
            if let u = unit {
                cartTotalLabel.text = "\(rounded) \(u)"
            } else {
                cartTotalLabel.text = "\(rounded)"
            }
        }
    }

    private func addPlacedItem(_ item: [String: Any]) {
        placedItems.append(item)
        updateCartUI()
        if enablePanDebugPrints { print("CART: added item -> now \(placedItems.count) items, total=\(cartTotalLabel.text ?? "")") }
    }

    private func removePlacedItem(at index: Int) {
        guard index >= 0 && index < placedItems.count else { return }
        placedItems.remove(at: index)
        updateCartUI()
        if enablePanDebugPrints { print("CART: removed item -> now \(placedItems.count) items") }
    }



    // VirtualObjectViewController.swift
    // central place to read Mac IP (change default as needed or make this read from user settings)
    func getMacIP() -> String {
        // TODO: replace with a stored setting or UI input later; hard-coded for now.
        return "172.20.10.3"
    }

}

extension VirtualObjectViewController: ARSCNViewDelegate {

    public func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            guard
                let center = self.screenCenter,
                let query = self.sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal)
            else { return }

            self.horizontalPlaneDetectedSubject.send(!self.sceneView.session.raycast(query).isEmpty)
        }
    }

}

extension VirtualObjectViewController: FloatingPaletteViewDelegate {
    // replace/implement delegate method (keep it non-public if required by your project)
    // Note: keep this method non-public if your delegate protocol is internal in your project.
    func floatingPalette(_ palette: FloatingPaletteView, didSelect type: VirtualObjectType) {
        if enablePanDebugPrints { print("PAL: selected \(type.rawValue) -> staging for placement (pending)") }

        // Stage selection: remember it so the Place button will place this type on next tap
        pendingSelectedType = type

        // Optionally pre-load the model into presenter's cache so subsequent placement is instant.
        // I assume presenter has (or you added) a method loadVirtualObject(named:). If not, loadVirtualObject is private:
        // You can add a small public/preload method in presenter or call addVirtualObject(ofType:...) with a no-op when not ready.
        // We'll attempt a preload via the presenter's load function if it exists (use `performSelector` style fallback to avoid compile errors).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.enablePanDebugPrints { print("PAL: preloading model '\(type.rawValue)' in background") }
            // If presenter exposes a preload API, call it — this example assumes `loadVirtualObject(named:)` is private.
            // If you created a public preload method, call that here. Fallback: attempt to load via addVirtualObject with an immediate invalid raycast check avoided.
            self.presenter.preloadVirtualObject(named: type.rawValue) // optional API if you added it to presenter
            if self.enablePanDebugPrints { print("PAL: preload for '\(type.rawValue)' completed (if supported)") }
        }

        // Provide immediate feedback to user: show selected thumbnail on the add button (optional)
        DispatchQueue.main.async {
            // If using UIButton.Configuration (iOS 15+), set an image on the left of the title
            if #available(iOS 15.0, *) {
                if var cfg = self.virtualObjectButton.configuration {
                    // If the palette or your assets include a 2D thumbnail, set it here. Otherwise, use a symbol to indicate selection.
                    let sym = UIImage(systemName: "checkmark.circle.fill")
                    cfg.image = sym
                    cfg.imagePadding = 8
                    cfg.imagePlacement = .leading
                    self.virtualObjectButton.configuration = cfg
                } else {
                    var cfg = UIButton.Configuration.plain()
                    cfg.title = LocalizableStrings.addVirtualObject.localized
                    cfg.image = UIImage(systemName: "checkmark.circle.fill")
                    cfg.imagePadding = 8
                    cfg.baseForegroundColor = .white
                    self.virtualObjectButton.configuration = cfg
                }
            } else {
                // fallback: set accessory image by using setImage (make sure not to override title)
                let sym = UIImage(systemName: "checkmark.circle.fill")
                self.virtualObjectButton.setImage(sym, for: .normal)
                self.virtualObjectButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
            }

            // Optionally collapse the palette visually (or leave expanded until user taps Place)
            // self.setPaletteCollapsed(true, animated: true)
        }
    }


    func floatingPaletteDidToggle(_ palette: FloatingPaletteView, expanded: Bool) {
        if enablePanDebugPrints { print("PAL: toggled expanded=\(expanded)") }
        // optional: animate or adjust other UI if needed
    }
}

private extension SCNVector3 {
    static func - (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        return SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        return SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }
}
