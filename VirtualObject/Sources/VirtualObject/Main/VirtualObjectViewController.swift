import ARKit
import Combine
import UIKit
import Core
import CoreUi

public class VirtualObjectViewController: UIViewController, UIGestureRecognizerDelegate {

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

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIApplication.shared.isIdleTimerDisabled = true
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

        // Populate items now
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

    private func populatePaletteItems() {
        // clear
        paletteStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Get object list. Prefer CaseIterable on VirtualObjectType
        let types: [VirtualObjectType]
        if let _ = (VirtualObjectType.self as? CaseIterable.Type) {
            types = (VirtualObjectType.allCases as? [VirtualObjectType]) ?? []
        } else {
            // fallback: ask presenter if it exposes a list (implement presenter.availableTypes() if needed)
            if let list = (presenter as? AnyObject)?.value(forKey: "availableTypes") as? [VirtualObjectType] {
                types = list
            } else {
                types = []
            }
        }

        for (index, type) in types.enumerated() {
            // create a compact card view (reuse your VirtualObjectCardView if exists)
            let card = VirtualObjectCardView(frame: .zero)
            card.translatesAutoresizingMaskIntoConstraints = false

            // store index so tap handler can find the selected type reliably
            card.tag = index

            // configure card (use readable title and thumbnail if available)
            // Prefer `title` if your VirtualObjectType provides it; otherwise use rawValue
            let displayTitle: String
            if let mirrorTitle = (type as? CustomStringConvertible)?.description {
                displayTitle = mirrorTitle
            } else {
                displayTitle = type.rawValue
            }
            card.titleLabel?.text = displayTitle

            // Attempt to load a 2D thumbnail from bundle with the same rawValue name (replace with your actual asset name mapping)
            if let imgView = card.imageView {
                if let thumb = UIImage(named: type.rawValue, in: .module, compatibleWith: nil) {
                    imgView.image = thumb
                } else {
                    // fallback to a system icon so UI is not empty
                    imgView.image = UIImage(systemName: "cube.box")
                }
                imgView.contentMode = .scaleAspectFit
            }

            // interaction
            let tap = UITapGestureRecognizer(target: self, action: #selector(paletteItemTapped(_:)))
            card.addGestureRecognizer(tap)
            card.isUserInteractionEnabled = true

            // visual defaults
            card.layer.borderWidth = 0
            card.layer.borderColor = UIColor.clear.cgColor
            card.backgroundColor = UIColor(white: 1.0, alpha: 0.0) // transparent by default

            // set a small fixed height so scroll content looks consistent
            card.heightAnchor.constraint(equalToConstant: 72).isActive = true

            paletteStack.addArrangedSubview(card)
        }

        // if empty, show a helpful label
        if types.isEmpty {
            let lbl = UILabel()
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.text = "No objects"
            lbl.textColor = .white
            lbl.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            lbl.textAlignment = .center
            lbl.heightAnchor.constraint(equalToConstant: 44).isActive = true
            paletteStack.addArrangedSubview(lbl)
        }

        // Ensure palette scroll view content is updated
        paletteScrollView?.setNeedsLayout()
        paletteScrollView?.layoutIfNeeded()
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

        let idx = card.tag
        guard idx >= 0 && idx < types.count else {
            if enablePanDebugPrints { print("PAL: paletteItemTapped - invalid index \(idx)") }
            return
        }

        let selectedType = types[idx]
        if enablePanDebugPrints { print("PAL: paletteItemTapped -> selected \(selectedType.rawValue) (index \(idx))") }

        // Save selection for the "Place Item" button to use later
        selectedTypeForPlacement = selectedType

        // Clear visual selection on all cards (no dependency on FloatingPaletteView API)
        paletteStack.arrangedSubviews.forEach { sub in
            if let c = sub as? VirtualObjectCardView {
                c.layer.borderWidth = 0
                c.layer.borderColor = UIColor.clear.cgColor
                // optional: reset background
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

