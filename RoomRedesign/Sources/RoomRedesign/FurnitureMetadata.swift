import Foundation
import simd

// ============================================================================
// DYNAMIC FURNITURE METADATA FROM LLM RESPONSE
// ============================================================================

/// Apply dynamic positioning based on furniture item from LLM
 func applyDynamicFurniturePosition(
    item: PlacedFurniture,
    furnitureData: FurnitureItem,
    floorHeight: Float,
    polygon: [SIMD2<Float>]
) -> PlacedFurniture {
    
    let dimensions = furnitureData.dimensionsInMeters
    
    // For beds, align to nearest wall
    if furnitureData.category.lowercased() == "bed" {
        return alignBedToWall(item: item, floorHeight: floorHeight, polygon: polygon)
    }
    
    // Place furniture on floor
    let adjustedPosition = SIMD3<Float>(
        item.position.x,
        floorHeight + 0.01,  // Tiny offset to prevent z-fighting
        item.position.z
    )
    
    return PlacedFurniture(
        position: adjustedPosition,
        rotation: item.rotation,
        category: item.category
    )
}

// ============================================================================
// BED WALL ALIGNMENT
// ============================================================================

/// Align bed to nearest wall instead of placing in middle
func alignBedToWall(
    item: PlacedFurniture,
    floorHeight: Float,
    polygon: [SIMD2<Float>]
) -> PlacedFurniture {
    
    let pos2D = SIMD2<Float>(item.position.x, item.position.z)
    
    // Find nearest wall edge
    var nearestEdge: (start: SIMD2<Float>, end: SIMD2<Float>)?
    var minDistance: Float = .infinity
    
    for i in 0..<polygon.count {
        let start = polygon[i]
        let end = polygon[(i + 1) % polygon.count]
        
        let distance = distanceToLineSegment(point: pos2D, lineStart: start, lineEnd: end)
        
        if distance < minDistance {
            minDistance = distance
            nearestEdge = (start, end)
        }
    }
    
    guard let edge = nearestEdge else { return item }
    
    // Calculate wall direction
    let wallDirection = edge.end - edge.start
    let wallAngle = atan2(wallDirection.y, wallDirection.x) * 180.0 / .pi
    
    // Get wall normal (perpendicular to wall)
    let wallNormal = SIMD2<Float>(-wallDirection.y, wallDirection.x)
    let normalizedNormal = normalize(wallNormal)
    
    // Position bed 0.3m from wall (headboard against wall)
    let wallOffset: Float = 0.3
    let newPos2D = projectPointToLine(point: pos2D, lineStart: edge.start, lineEnd: edge.end) + normalizedNormal * wallOffset
    
    // ✅ FIX: Bed should be PARALLEL to wall (headboard against wall)
    // The longer side should be parallel to wall
    let bedRotation = wallAngle+90  // NOT wallAngle + 90
    
    print("🛏️ Aligned bed to wall at \(String(format: "%.1f", bedRotation))° (parallel to wall)")
    
    return PlacedFurniture(
        position: SIMD3<Float>(newPos2D.x, floorHeight + 0.01, newPos2D.y),
        rotation: bedRotation,  // Parallel to wall
        category: item.category
    )
}

// ============================================================================
// GEOMETRY HELPERS
// ============================================================================

private func distanceToLineSegment(point: SIMD2<Float>, lineStart: SIMD2<Float>, lineEnd: SIMD2<Float>) -> Float {
    let line = lineEnd - lineStart
    let lineLength = length(line)
    
    guard lineLength > 0.001 else {
        return length(point - lineStart)
    }
    
    let t = max(0, min(1, dot(point - lineStart, line) / (lineLength * lineLength)))
    let projection = lineStart + line * t
    
    return length(point - projection)
}

func projectPointToLine(point: SIMD2<Float>, lineStart: SIMD2<Float>, lineEnd: SIMD2<Float>) -> SIMD2<Float> {
    let line = lineEnd - lineStart
    let lineLength = length(line)
    
    guard lineLength > 0.001 else {
        return lineStart
    }
    
    let t = max(0, min(1, dot(point - lineStart, line) / (lineLength * lineLength)))
    return lineStart + line * t
}

// ============================================================================
// SMART ROTATION FOR LARGE FURNITURE
// ============================================================================

/// Apply smart rotation to furniture based on position and type
 func applySmartRotation(
    layout: [PlacedFurnitureWithMetadata],
    polygon: [SIMD2<Float>]
) -> [PlacedFurnitureWithMetadata] {
    
    guard !polygon.isEmpty else { return layout }
    
    print("🎯 Applying smart rotation...")
    
    return layout.map { item in
        let furniture = item.placement
        let metadata = item.metadata
        
        // Large furniture should face away from nearest wall
        let isLargeFurniture = metadata.size.lowercased() == "large" ||
                              metadata.category.lowercased() == "bed" ||
                              metadata.category.lowercased() == "sofa"
        
        if isLargeFurniture {
            let pos2D = SIMD2<Float>(furniture.position.x, furniture.position.z)
            
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
            
            // Use wall-based rotation (face away from wall)
            var rotation = nearestWallAngle + 90
            while rotation < 0 { rotation += 360 }
            while rotation >= 360 { rotation -= 360 }
            
            print("  🧭 \(metadata.itemName): \(String(format: "%.0f", rotation))° (wall-aligned)")
            
            let newPlacement = PlacedFurniture(
                position: furniture.position,
                rotation: rotation,
                category: furniture.category
            )
            
            return PlacedFurnitureWithMetadata(
                placement: newPlacement,
                metadata: metadata
            )
        }
        
        // Small furniture keeps AI's rotation
        print("  ✅ \(metadata.itemName): \(String(format: "%.0f", furniture.rotation))° (from AI)")
        return item
    }
}
