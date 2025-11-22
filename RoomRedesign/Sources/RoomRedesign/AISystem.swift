import Foundation
import simd
import RealityKit
import ModelIO
import UIKit

// ============================================================================
// PLACED FURNITURE STRUCTURE (SINGLE SOURCE OF TRUTH)
// ============================================================================

public struct PlacedFurniture: Codable {
    public let position: SIMD3<Float>
    public let rotation: Float
    public let category: String
    
    // Custom CodingKeys for AI JSON parsing
    enum CodingKeys: String, CodingKey {
        case category
        case position_x
        case position_y
        case position_z
        case rotation_y
    }
    
    // Decoder for AI JSON response
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawCategory = try container.decode(String.self, forKey: .category)
        
        category = rawCategory.replacingOccurrences(of: "_", with: " ")
        
        let x = try container.decode(Float.self, forKey: .position_x)
        let y = try container.decode(Float.self, forKey: .position_y)
        let z = try container.decode(Float.self, forKey: .position_z)
        position = SIMD3<Float>(x, y, z)
        
        rotation = try container.decode(Float.self, forKey: .rotation_y)
    }
    
    // Encoder for JSON serialization
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(position.x, forKey: .position_x)
        try container.encode(position.y, forKey: .position_y)
        try container.encode(position.z, forKey: .position_z)
        try container.encode(rotation, forKey: .rotation_y)
    }
    
    // Simple initializer for manual creation
    public init(position: SIMD3<Float>, rotation: Float, category: String) {
        self.position = position
        self.rotation = rotation
        self.category = category
    }
}

// ============================================================================
// LLM PLACEMENT RESPONSE (For Gemini API)
// ============================================================================

struct LLMPlacementResponse: Codable {
    let category: String
    let position_x: Float
    let position_z: Float
    let rotation_y: Float
}

// ============================================================================
// FURNITURE NORMALIZATION
// ============================================================================

public func findFirstModelEntity(in entity: Entity) -> ModelEntity? {
    if let m = entity as? ModelEntity { return m }
    for child in entity.children {
        if let found = findFirstModelEntity(in: child) { return found }
    }
    return nil
}

public func normalizeFurniture(_ entity: Entity, targetSize: SIMD3<Float>) -> (position: SIMD3<Float>, scale: SIMD3<Float>) {
    let bounds = entity.visualBounds(relativeTo: entity)
    let size = bounds.extents
    
    let scaleFactor = SIMD3<Float>(
        size.x > 0.001 ? targetSize.x / size.x : 1.0,
        size.y > 0.001 ? targetSize.y / size.y : 1.0,
        size.z > 0.001 ? targetSize.z / size.z : 1.0
    )
    
    let newY = -bounds.min.y * scaleFactor.y
    
    return (
        position: [0, newY, 0],
        scale: scaleFactor
    )
}
