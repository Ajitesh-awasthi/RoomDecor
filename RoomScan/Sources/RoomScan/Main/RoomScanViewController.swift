import Combine
import RoomPlan
import UIKit

public class RoomScanViewController: UIViewController {

    let defaultPadding: CGFloat = 16
    let cornerRadius: CGFloat = 4
    let buttonSize = CGSize(width: 80, height: 60)

    let sessionConfig: RoomCaptureSession.Configuration

    var roomCaptureView: RoomCaptureView!
    var saveButton: UIButton!
    var saveLoadingIndicator: UIActivityIndicatorView!
    var shareButton: UIButton!  // ✅ Keep name for compatibility
    var shareLoadingIndicator: UIActivityIndicatorView!

    private var disposables = Set<AnyCancellable>()
    private let presenter: RoomScanPresenter!
    private var capturedRoom: CapturedRoom?
    private var savedFileURL: URL?  // ✅ Store the saved file URL

    private var buttonTappedSubject = PassthroughSubject<ActionType, Never>()

    var buttonTapped: AnyPublisher<ActionType, Never> {
        buttonTappedSubject
            .delay(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    public init(presenter: RoomScanPresenter) {
        self.presenter = presenter
        self.sessionConfig = RoomCaptureSession.Configuration()

        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        buildViews()
        bindViews()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.isHidden = false
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        startSession()
    }

    private func bindViews() {
        presenter
            .$isReadyToSave
            .sink { [weak self] isReadyToSave in
                self?.saveButton.isHidden = !isReadyToSave
            }
            .store(in: &disposables)

        saveButton
            .throttledTap()
            .sink { [weak self] _ in
                guard let self else { return }

                self.showLoader(for: .save)
                self.buttonTappedSubject.send(.save)
            }
            .store(in: &disposables)

        // ✅ FIX: Change shareButton behavior to navigate to redesign
        shareButton
            .throttledTap()
            .sink { [weak self] _ in
                guard let self else { return }
                
                print("🎨 Redesign button tapped!")
                
                // Make sure we have a saved file
                guard let fileURL = self.savedFileURL else {
                    print("❌ No saved file available yet!")
                    return
                }
                
                // Verify file exists
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("❌ Saved file doesn't exist: \(fileURL.path)")
                    return
                }
                
                print("✅ Navigating to redesign with file: \(fileURL.lastPathComponent)")
                
                // Navigate to redesign UI
                self.presenter.appRouter.presentRedesignUI(for: fileURL)
            }
            .store(in: &disposables)

        buttonTapped
            .sink { [weak self] type in
                guard let self else { return }

                switch type {
                case .save:
                    self.saveTapped()
                case .share:
                    // No longer used - redesign button handles this directly
                    break
                }
            }
            .store(in: &disposables)
    }

    private func startSession() {
        roomCaptureView.captureSession.run(configuration: sessionConfig)
    }

    private func stopSession() {
        roomCaptureView.captureSession.stop()
    }

    private func saveTapped() {
        print("\n💾 === SAVE BUTTON TAPPED ===")
        saveRoomScan()
        stopSession()
        saveButton.isHidden = true
        hideLoader(for: .save)
    }

    private func saveRoomScan() {
        print("💾 Starting save process...")
        
        guard let capturedRoom = capturedRoom else {
            print("❌ ERROR: No captured room to save!")
            presenter.showErrorPopup(for: .save)
            return
        }
        
        let url = presenter.exportUrl
        print("📁 Export URL: \(url.path)")
        print("📁 Filename: \(url.lastPathComponent)")
        
        do {
            print("💾 Exporting room to file...")
            try capturedRoom.export(to: url)
            print("✅ Export completed successfully!")
            
            // Verify file was created
            if FileManager.default.fileExists(atPath: url.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    print("✅ File saved successfully!")
                    print("📦 File size: \(size) bytes")
                    
                    // ✅ Store the saved file URL for later use
                    self.savedFileURL = url
                    
                    if size == 0 {
                        print("⚠️ WARNING: File size is 0 bytes!")
                    }
                }
            } else {
                print("❌ ERROR: File doesn't exist after export!")
            }
            
        } catch {
            print("❌ ERROR: Failed to export room!")
            print("❌ Error details: \(error.localizedDescription)")
            presenter.showErrorPopup(for: .save)
        }
    }

    private func showLoader(for action: ActionType) {
        switch action {
        case .save:
            self.saveLoadingIndicator.isHidden = false
            self.saveLoadingIndicator.startAnimating()
            self.saveButton.titleLabel?.isHidden = true
        case .share:
            self.shareLoadingIndicator.isHidden = false
            self.shareLoadingIndicator.startAnimating()
            self.shareButton.titleLabel?.isHidden = true
        }
    }

    private func hideLoader(for action: ActionType) {
        switch action {
        case .save:
            self.saveLoadingIndicator.isHidden = true
            self.saveLoadingIndicator.stopAnimating()
            self.saveButton.titleLabel?.isHidden = false
        case .share:
            self.shareLoadingIndicator.isHidden = true
            self.shareLoadingIndicator.stopAnimating()
            self.shareButton.titleLabel?.isHidden = false
        }
    }

}

// MARK: - RoomCaptureSessionDelegate
extension RoomScanViewController: RoomCaptureSessionDelegate {

    public func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        capturedRoom = room
        print("🔄 Room updated - ready to save")
        DispatchQueue.main.async {
            self.presenter.isReadyToSave = true
        }
    }

    public func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        print("\n🏁 === CAPTURE SESSION ENDED ===")
        
        DispatchQueue.main.async {
            guard error == nil else {
                print("❌ Session ended with error: \(error!.localizedDescription)")
                self.presenter.showErrorPopup(for: .session)
                return
            }

            print("✅ Session ended successfully")
            
            // ✅ FIX: Show button (don't auto-save again!)
            UIView.animate(withDuration: 0.2, delay: 1.5) {
                self.shareButton.layer.opacity = 1
                print("✅ Redesign button now visible")
            }
        }
    }

}
