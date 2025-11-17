import Foundation
import simd

// ============================================================================
// FURNITURE METADATA SYSTEM
// ============================================================================


/// Metadata for each furniture type
public struct FurnitureMetadata {
    let category: String
    let heightOffset: Float
    let shouldFaceAwayFromWall: Bool
    let canRotate: Bool
    let price: Float
    
    init(
        category: String,
        heightOffset: Float = 0.0,
        shouldFaceAwayFromWall: Bool = false,
        canRotate: Bool = true,
        price: Float = 0.0
    ) {
        self.category = category
        self.heightOffset = heightOffset
        self.shouldFaceAwayFromWall = shouldFaceAwayFromWall
        self.canRotate = canRotate
        self.price = price
    }
}

/// Global furniture metadata registry
public let furnitureMetadata: [String: FurnitureMetadata] = [
    "Sofa": FurnitureMetadata(
        category: "Sofa",
        shouldFaceAwayFromWall: true,
        price: 899.99
    ),
    "Table": FurnitureMetadata(
        category: "Table",
        price: 149.99
    ),
    "Lamp": FurnitureMetadata(
        category: "Lamp",
        canRotate: false,
        price: 79.50
    ),
    "Study Desk": FurnitureMetadata(
        category: "Study Desk",
        shouldFaceAwayFromWall: true,
        price: 229.00
    ),
    "Office Chair": FurnitureMetadata(
        category: "Office Chair",
        shouldFaceAwayFromWall: true,
        price: 179.99
    ),
    "Bookshelf": FurnitureMetadata(
        category: "Bookshelf",
        shouldFaceAwayFromWall: true,
        price: 199.99
    ),
    "Bed": FurnitureMetadata(
        category: "Bed",
        shouldFaceAwayFromWall: true,
        price: 799.00
    ),
    "Wardrobe": FurnitureMetadata(
        category: "Wardrobe",
        heightOffset: 0.0,
        shouldFaceAwayFromWall: true,
        price: 549.00
    ),
    "Dressing_Table": FurnitureMetadata(
        category: "Dressing_Table",
        shouldFaceAwayFromWall: true,
        price: 249.00
    ),
    "Painting": FurnitureMetadata(
        category: "Painting",
        heightOffset: 1.5,
        canRotate: false,
        price: 89.99
    ),
    "Wall_Clock": FurnitureMetadata(
        category: "Wall_Clock",
        heightOffset: 2.0,
        canRotate: false,
        price: 49.99
    ),
    "Pot": FurnitureMetadata(
        category: "Pot",
        canRotate: false,
        price: 35.00
    )
]

// ============================================================================
// APPLY METADATA
// ============================================================================

public func applyFurnitureMetadata(
    item: PlacedFurniture,
    floorHeight: Float
) -> PlacedFurniture {
    
    guard let metadata = furnitureMetadata[item.category] else {
           // For items without metadata, place ON floor
           let adjustedPosition = SIMD3<Float>(
               item.position.x,
               floorHeight,
               item.position.z
           )
           return PlacedFurniture(
               position: adjustedPosition,
               rotation: item.rotation,
               category: item.category
           )
       }
    
    // Apply correct height based on metadata
    let adjustedY: Float
    
    if isWallItem(item.category) {
        // Wall items use their specified height offset
        adjustedY = floorHeight + metadata.heightOffset
        print("🖼️ Placing \(item.category) at height \(adjustedY) (floor: \(floorHeight) + offset: \(metadata.heightOffset))")
    } else {
        // Floor items should be ON the floor
        adjustedY = floorHeight + 0.01  // Tiny offset to prevent z-fighting
    }
    
    let adjustedPosition = SIMD3<Float>(
        item.position.x,
        adjustedY,
        item.position.z
    )
    
    return PlacedFurniture(
        position: adjustedPosition,
        rotation: item.rotation,
        category: item.category
    )
}
// ============================================================================
// SMART ROTATION
// ============================================================================

/// Smart rotation that respects AI's decisions
public func alignLayoutRotationsRespectingAI(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>]
) -> [PlacedFurniture] {
    
    guard !polygon.isEmpty else { return layout }
    
    print("🎯 Smart rotation (respecting AI's decisions)...")
    
    return layout.map { item in
        // Get metadata
        guard let metadata = furnitureMetadata[item.category] else {
            print("  ℹ️ \(item.category): No metadata, using AI rotation \(String(format: "%.0f", item.rotation))°")
            return item
        }
        
        // If furniture can't rotate, force to 0
        if !metadata.canRotate {
            print("  🔒 \(item.category): Fixed at 0° (non-rotatable)")
            return PlacedFurniture(
                position: item.position,
                rotation: 0.0,
                category: item.category
            )
        }
        
        // If furniture should face wall
        if metadata.shouldFaceAwayFromWall {
            let pos2D = SIMD2<Float>(item.position.x, item.position.z)
            
            // Find nearest wall
            var nearestWallAngle: Float = 0
            var minDistance = Float.infinity
            
            for i in 0..<polygon.count {
                let j = (i + 1) % polygon.count
                let p1 = polygon[i]
                let p2 = polygon[j]
                
                let edge = p2 - p1
                let toPoint = pos2D - p1
                let edgeLengthSquared = dot(edge, edge)
                
                if edgeLengthSquared < 0.0001 { continue }
                
                let t = max(0.0, min(1.0, dot(toPoint, edge) / edgeLengthSquared))
                let projection = p1 + edge * t
                let distance = length(pos2D - projection)
                
                if distance < minDistance {
                    minDistance = distance
                    let wallDirection = p2 - p1
                    nearestWallAngle = atan2(wallDirection.y, wallDirection.x) * 180.0 / .pi
                }
            }
            
            // Use wall-based rotation
            var rotation = nearestWallAngle + 90
            while rotation < 0 { rotation += 360 }
            while rotation >= 360 { rotation -= 360 }
            
            print("  🧭 \(item.category): \(String(format: "%.0f", rotation))° (wall-aligned)")
            
            return PlacedFurniture(
                position: item.position,
                rotation: rotation,
                category: item.category
            )
        }
        
        // Otherwise, use AI's rotation
        print("  ✅ \(item.category): \(String(format: "%.0f", item.rotation))° (from AI)")
        return item
    }
}

// ============================================================================
// MAIN PROCESSING FUNCTION
// ============================================================================

/// Process complete layout with metadata
public func processLayoutWithMetadata(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    floorHeight: Float,
    rotationStrategy: String = "smart"
) -> [PlacedFurniture] {
    
    print("\n🔧 Processing layout with metadata system...")
    
    // Step 1: Apply height offsets
    print("\n📏 Applying height offsets...")
    var processedLayout = layout.map { item in
        applyFurnitureMetadata(item: item, floorHeight: floorHeight)
    }
    
    // Step 2: Apply rotation strategy
    print("\n🔄 Applying rotation strategy: \(rotationStrategy)")
    switch rotationStrategy {
    case "smart":
        processedLayout = alignLayoutRotationsRespectingAI(
            layout: processedLayout,
            polygon: polygon
        )
    case "trust_ai":
        print("  ✅ Using AI's rotations as-is")
    case "simple":
        processedLayout = processedLayout.map { item in
            PlacedFurniture(
                position: item.position,
                rotation: 0.0,
                category: item.category
            )
        }
        print("  🔒 All furniture set to 0°")
    default:
        print("  ⚠️ Unknown rotation strategy '\(rotationStrategy)', using AI's rotations")
    }
    
    print("\n✅ Layout processing complete")
    return processedLayout
}

// Helper to check if item is a wall decoration
private func isWallItem(_ category: String) -> Bool {
    return category == "Painting" ||
           category == "Wall_Clock" ||
           category == "Wall Clock"
}
