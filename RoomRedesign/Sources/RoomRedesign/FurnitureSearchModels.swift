import Foundation
import simd

// ============================================================================
// FURNITURE SEARCH RESPONSE FROM LLM
// ============================================================================

struct FurnitureSearchResponse: Codable {
    let isRelaxed: Bool
    let results: [FurnitureItem]
}

struct FurnitureItem: Codable, Identifiable {
    let rating: Float
    let price: Float
    let priceUnit: String
    let itemName: String
    let imageLink2D: String
    let imageLink3D: String
    let size: String
    let category: String
    let length: Float // in cm (JSON sends as number, e.g., 80.0)
        let width: Float  // in cm
        let height: Float // in cm
    let dimUnit: String
    
    var id: String { itemName }
    
    // Convert dimensions from cm to meters
    var dimensionsInMeters: SIMD3<Float> {
        return SIMD3<Float>(
            Float(width) / 100.0,   // width → X
            Float(height) / 100.0,  // height → Y
            Float(length) / 100.0   // length → Z
        )
    }
    
    // Get the actual USDZ URL for loading the 3D model
    var usdz3DUrl: URL? {
        return URL(string: imageLink3D)
    }
}

// ============================================================================
// PLACED FURNITURE WITH API METADATA
// ============================================================================

struct PlacedFurnitureWithMetadata: Identifiable {
    let placement: PlacedFurniture  // Position, rotation, category
    let metadata: FurnitureItem     // Price, images, dimensions from LLM
    
    var id: String { metadata.itemName }
    var price: Float { metadata.price }
    var imageURL: String { metadata.imageLink2D }
    var modelURL: String { metadata.imageLink3D }
}
