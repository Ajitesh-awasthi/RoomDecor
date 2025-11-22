import Foundation
import simd

// ============================================================================
// COLLISION DETECTION & OVERLAP PREVENTION
// ============================================================================

/// Represents a 2D bounding box for furniture collision detection
struct FurnitureBounds2D {
    let center: SIMD2<Float>
    let halfExtents: SIMD2<Float>
    let rotation: Float
    
    /// Get the four corners of the rotated bounding box
    func getCorners() -> [SIMD2<Float>] {
        let cos = cosf(rotation * .pi / 180.0)
        let sin = sinf(rotation * .pi / 180.0)
        
        let localCorners: [SIMD2<Float>] = [
            SIMD2(-halfExtents.x, -halfExtents.y),
            SIMD2( halfExtents.x, -halfExtents.y),
            SIMD2( halfExtents.x,  halfExtents.y),
            SIMD2(-halfExtents.x,  halfExtents.y)
        ]
        
        return localCorners.map { local in
            let rotated = SIMD2(
                local.x * cos - local.y * sin,
                local.x * sin + local.y * cos
            )
            return center + rotated
        }
    }
}

/// Get 2D bounds for a furniture item using its actual dimensions
func getBounds2D(for item: PlacedFurniture, dimensions: SIMD3<Float>) -> FurnitureBounds2D {
    return FurnitureBounds2D(
        center: SIMD2(item.position.x, item.position.z),
        halfExtents: SIMD2(dimensions.x / 2, dimensions.z / 2),
        rotation: item.rotation
    )
}

/// Check if two oriented bounding boxes overlap using Separating Axis Theorem (SAT)
func checkOverlap(bounds1: FurnitureBounds2D, bounds2: FurnitureBounds2D, minDistance: Float = 0.3) -> Bool {
    
    let corners1 = bounds1.getCorners()
    let corners2 = bounds2.getCorners()
    
    var axes: [SIMD2<Float>] = []
    
    // Get axes from first box
    for i in 0..<4 {
        let edge = corners1[(i + 1) % 4] - corners1[i]
        let axis = SIMD2(-edge.y, edge.x)
        let normalized = normalize(axis)
        axes.append(normalized)
    }
    
    // Get axes from second box
    for i in 0..<4 {
        let edge = corners2[(i + 1) % 4] - corners2[i]
        let axis = SIMD2(-edge.y, edge.x)
        let normalized = normalize(axis)
        axes.append(normalized)
    }
    
    // Test each axis
    for axis in axes {
        let proj1 = corners1.map { dot($0, axis) }
        let min1 = proj1.min()!
        let max1 = proj1.max()!
        
        let proj2 = corners2.map { dot($0, axis) }
        let min2 = proj2.min()!
        let max2 = proj2.max()!
        
        if max1 + minDistance < min2 || max2 + minDistance < min1 {
            return false
        }
    }
    
    return true
}

/// Remove overlapping furniture from layout
public func removeOverlappingFurniture(
    layout: [PlacedFurniture],
    minDistance: Float = 0.3,
    dimensionsMap: [String: SIMD3<Float>] = [:]
) -> [PlacedFurniture] {
    
    print("\n🔍 Checking for overlapping furniture...")
    
    var validItems: [PlacedFurniture] = []
    var removedItems: [String] = []
    
    for item in layout {
        let dimensions = dimensionsMap[item.category] ?? SIMD3<Float>(1.0, 1.0, 1.0)
        var hasOverlap = false
        
        for existing in validItems {
            let existingDimensions = dimensionsMap[existing.category] ?? SIMD3<Float>(1.0, 1.0, 1.0)
            
            let newBounds = getBounds2D(for: item, dimensions: dimensions)
            let existingBounds = getBounds2D(for: existing, dimensions: existingDimensions)
            
            if checkOverlap(bounds1: newBounds, bounds2: existingBounds, minDistance: minDistance) {
                print("  ❌ \(item.category) overlaps with \(existing.category)")
                hasOverlap = true
                break
            }
        }
        
        if hasOverlap {
            print("  🗑️ Removing overlapping \(item.category)")
            removedItems.append(item.category)
        } else {
            validItems.append(item)
            print("  ✅ \(item.category) is valid (no overlaps)")
        }
    }
    
    if !removedItems.isEmpty {
        print("\n⚠️ Removed \(removedItems.count) overlapping items: \(removedItems.joined(separator: ", "))")
    } else {
        print("\n✅ No overlaps detected - all furniture valid!")
    }
    
    return validItems
}

/// Find a nearby non-overlapping position for furniture
func findNonOverlappingPosition(
    for item: PlacedFurniture,
    dimensions: SIMD3<Float>,
    existingItems: [PlacedFurniture],
    existingDimensions: [String: SIMD3<Float>],
    polygon: [SIMD2<Float>]
) -> PlacedFurniture? {
    
    let searchRadius: Float = 0.5
    let angleStep: Float = 30.0
    let radiusStep: Float = 0.3
    
    for radius in stride(from: searchRadius, through: searchRadius * 3, by: radiusStep) {
        for angle in stride(from: Float(0.0), to: Float(360.0), by: angleStep) {
            let angleRad = angle * .pi / 180.0
            let offset = SIMD2<Float>(
                radius * cos(angleRad),
                radius * sin(angleRad)
            )
            
            let newPos2D = SIMD2(item.position.x, item.position.z) + offset
            let newPosition = SIMD3(newPos2D.x, item.position.y, newPos2D.y)
            
            let testItem = PlacedFurniture(
                position: newPosition,
                rotation: item.rotation,
                category: item.category
            )
            
            if isPointInPolygonWithMargin(point: newPos2D, polygon: polygon, margin: 0.4) {
                var hasOverlap = false
                for existing in existingItems {
                    let existingDim = existingDimensions[existing.category] ?? SIMD3<Float>(1.0, 1.0, 1.0)
                    let testBounds = getBounds2D(for: testItem, dimensions: dimensions)
                    let existingBounds = getBounds2D(for: existing, dimensions: existingDim)
                    
                    if checkOverlap(bounds1: testBounds, bounds2: existingBounds, minDistance: 0.3) {
                        hasOverlap = true
                        break
                    }
                }
                
                if !hasOverlap {
                    print("  ✅ Found valid position for \(item.category) at offset \(offset)")
                    return testItem
                }
            }
        }
    }
    
    print("  ❌ Could not find valid position for \(item.category)")
    return nil
}
