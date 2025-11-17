import Combine
import Foundation
import Core

public class RoomScanPresenter {

    @Published var isReadyToSave: Bool = false

    // ✅ Make appRouter public so RoomScanViewController can access it
    public let appRouter: RoomScanRouterProtocol

    public init(appRouter: RoomScanRouterProtocol) {
        self.appRouter = appRouter
    }

    func presentShareSheet() {
        appRouter.presentShareSheet(for: [exportUrl])
    }

    func showErrorPopup(for type: RoomScanErrorType) {
        appRouter.showErrorPopup(for: type)
    }

}

extension RoomScanPresenter {

    var exportUrl: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // ✅ Use DateFormatter to avoid colons in filename
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: Date())
        
        let fileName = "scan_"
            .appending(dateString)
            .appending(FileType.usdz.fileExtension)
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        print("📁 Saving scan to: \(fileURL.path)")
        print("📁 Filename: \(fileName)")
        
        return fileURL
    }

}
