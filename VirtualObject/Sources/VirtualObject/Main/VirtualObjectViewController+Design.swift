import ARKit
import UIKit
import SnapKit
import CoreUi

extension VirtualObjectViewController {

    func buildViews() {
        createViews()
        styleViews()
        defineLayoutForViews()
    }

    // Replace createViews()
    public func createViews() {
        print("DBG: createViews() - start")

        // Scene view (full screen)
        sceneView = ARSCNView()
        sceneView.setUp(session)
        sceneView.delegate = self
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)

        // Sight image in center
        sightImageView = UIImageView()
        sightImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sightImageView)

        // Info view above button
        infoView = InfoView()
        infoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoView)

        // Virtual object button - system type so it shows title by default
        virtualObjectButton = UIButton(type: .system)
        virtualObjectButton.translatesAutoresizingMaskIntoConstraints = false
        virtualObjectButton.accessibilityIdentifier = "virtualObjectButton"
        // Ensure visible and interactive
        virtualObjectButton.isHidden = false
        virtualObjectButton.alpha = 1.0
        virtualObjectButton.isUserInteractionEnabled = true
        view.addSubview(virtualObjectButton)

        // Ensure the button is on top of the sceneView
        view.bringSubviewToFront(virtualObjectButton)

        print("DBG: createViews() - added subviews. view.subviews.count = \(view.subviews.count)")
        print("DBG: createViews() - sceneView.superview != nil -> \(sceneView.superview != nil)")
        print("DBG: createViews() - virtualObjectButton.superview != nil -> \(virtualObjectButton.superview != nil)")
        print("DBG: createViews() - end")
    }


    // Replace styleViews()
    public func styleViews() {
        print("DBG: styleViews() - start")
        navigationController?.setNavigationBarHidden(false, animated: false)

        // Sight image
        sightImageView.image = UIImage(named: BundleImage.sight.rawValue, in: .module, with: nil)
        sightImageView.contentMode = .scaleAspectFit
        sightImageView.isHidden = false

        // Info view
        infoView.set(title: LocalizableStrings.infoLabel.localized)

        // Button: use configuration on iOS 15+, fallback otherwise
        let title = LocalizableStrings.addVirtualObject.localized
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = title
            config.baseBackgroundColor = .black
            config.baseForegroundColor = .white
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            virtualObjectButton.configuration = config
        } else {
            virtualObjectButton.setTitle(title, for: .normal)
            virtualObjectButton.setTitleColor(.white, for: .normal)
            virtualObjectButton.backgroundColor = .black
            virtualObjectButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        }
        virtualObjectButton.roundAllCorners(withRadius: cornerRadius)
        virtualObjectButton.layer.zPosition = 1000 // ensure it's above AR content

        // Add a quick tap target for debugging (keeps previous throttledTap binding intact)
        virtualObjectButton.addTarget(self, action: #selector(debugButtonTapped(_:)), for: .touchUpInside)

        print("DBG: styleViews() - virtualObjectButton title = \(virtualObjectButton.title(for: .normal) ?? "<nil>")")
        print("DBG: styleViews() - virtualObjectButton configuration != nil -> \((virtualObjectButton.configuration != nil))")
        print("DBG: styleViews() - end")
    }

    @objc private func debugButtonTapped(_ sender: UIButton) {
        print("DBG: virtualObjectButton tapped — frame = \(virtualObjectButton.frame), hidden=\(virtualObjectButton.isHidden), alpha=\(virtualObjectButton.alpha)")
    }


    // Replace defineLayoutForViews()
    public func defineLayoutForViews() {
        print("DBG: defineLayoutForViews() - start")

        // sceneView fills whole screen
        sceneView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }

        // sight image at center
        sightImageView.snp.remakeConstraints {
            $0.center.equalToSuperview()
            $0.size.equalTo(sightImageSize)
        }

        // virtualObjectButton bottom center, with safe area
        virtualObjectButton.snp.remakeConstraints {
            $0.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(defaultPadding * 3)
            $0.leading.trailing.equalToSuperview().inset(defaultPadding * 2)
            $0.height.equalTo(buttonHeight)
        }

        // infoView above the button
        infoView.snp.remakeConstraints {
            $0.bottom.equalTo(virtualObjectButton.snp.top).offset(-defaultPadding)
            $0.leading.trailing.equalToSuperview().inset(defaultPadding * 2)
            $0.height.equalTo(44)
        }

        // Bring button to front again after constraints
        view.layoutIfNeeded()
        view.bringSubviewToFront(virtualObjectButton)
        view.bringSubviewToFront(sightImageView)
        view.bringSubviewToFront(infoView)

        // Debug layout frames
        DispatchQueue.main.async {
            print("DBG: defineLayoutForViews() - after layout:")
            print("    sceneView.frame = \(self.sceneView.frame)")
            print("    sightImageView.frame = \(self.sightImageView.frame)")
            print("    infoView.frame = \(self.infoView.frame)")
            print("    virtualObjectButton.frame = \(self.virtualObjectButton.frame)")
            print("    safeAreaInsets = \(self.view.safeAreaInsets)")
            print("    virtualObjectButton.isHidden = \(self.virtualObjectButton.isHidden)")
            print("    virtualObjectButton.alpha = \(self.virtualObjectButton.alpha)")
            print("    virtualObjectButton.superview = \(String(describing: self.virtualObjectButton.superview))")
            print("    subview order (top -> bottom):")
            for sv in self.view.subviews.reversed() {
                print("       \(type(of: sv)) frame=\(sv.frame) hidden=\(sv.isHidden) alpha=\(sv.alpha)")
            }
        }

        print("DBG: defineLayoutForViews() - end")
    }


    @objc public func backTapped() {
        navigationController?.popViewController(animated: true)
        // or: dismiss(animated: true) if presented modally
    }

}
