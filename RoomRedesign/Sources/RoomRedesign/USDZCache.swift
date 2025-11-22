import Foundation
import RealityKit

class USDZCache {
    static let shared = USDZCache()
    private let cacheDirectory: URL
    
    private init() {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesURL.appendingPathComponent("USDZModels", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Downloads USDZ from URL and returns local file URL
    func downloadAndCache(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "USDZCache", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Create a safe filename from the URL
        let filename = url.lastPathComponent
        let localURL = cacheDirectory.appendingPathComponent(filename)
        
        // Check if already cached
        if FileManager.default.fileExists(atPath: localURL.path) {
            print("✅ Using cached USDZ: \(filename)")
            return localURL
        }
        
        print("⬇️ Downloading USDZ: \(filename)")
        
        // Download the file
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "USDZCache", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to download file"])
        }
        
        // Move to cache directory
        try? FileManager.default.removeItem(at: localURL) // Remove if exists
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        
        print("✅ Cached USDZ: \(filename)")
        return localURL
    }
    
    /// Load entity from remote USDZ URL
    func loadEntity(from urlString: String) async throws -> Entity {
        let localURL = try await downloadAndCache(from: urlString)
        return try await Entity.load(contentsOf: localURL)
    }
    
    /// Completion handler version for non-async code
    func loadEntity(from urlString: String, completion: @escaping (Result<Entity, Error>) -> Void) {
        Task {
            do {
                let entity = try await loadEntity(from: urlString)
                await MainActor.run {
                    completion(.success(entity))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Clear all cached files
    func clearCache() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for fileURL in contents {
            try FileManager.default.removeItem(at: fileURL)
        }
        print("🗑️ Cache cleared")
    }
}
