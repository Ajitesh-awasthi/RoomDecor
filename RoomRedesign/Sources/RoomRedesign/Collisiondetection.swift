import Foundation
import simd

// ============================================================================
// COLLISION DETECTION & OVERLAP PREVENTION
// ============================================================================

/// Represents a 2D bounding box for furniture collision detection
struct FurnitureBounds2D {
    let center: SIMD2<Float>
    let halfExtents: SIMD2<Float>  // half width and half depth
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

/// Get 2D bounds for a furniture item
func getBounds2D(for item: PlacedFurniture) -> FurnitureBounds2D {
    let targetSize = getTargetSize(for: item.category)
    
    return FurnitureBounds2D(
        center: SIMD2(item.position.x, item.position.z),
        halfExtents: SIMD2(targetSize.x / 2, targetSize.z / 2),
        rotation: item.rotation
    )
}

/// Check if two oriented bounding boxes overlap using Separating Axis Theorem (SAT)
func checkOverlap(bounds1: FurnitureBounds2D, bounds2: FurnitureBounds2D, minDistance: Float = 0.3) -> Bool {
    
    // Get corners
    let corners1 = bounds1.getCorners()
    let corners2 = bounds2.getCorners()
    
    // Get axes to test (perpendicular to each edge)
    var axes: [SIMD2<Float>] = []
    
    // Axes from first box
    for i in 0..<4 {
        let edge = corners1[(i + 1) % 4] - corners1[i]
        let axis = SIMD2(-edge.y, edge.x)  // Perpendicular
        let normalized = normalize(axis)
        axes.append(normalized)
    }
    
    // Axes from second box
    for i in 0..<4 {
        let edge = corners2[(i + 1) % 4] - corners2[i]
        let axis = SIMD2(-edge.y, edge.x)  // Perpendicular
        let normalized = normalize(axis)
        axes.append(normalized)
    }
    
    // Test each axis
    for axis in axes {
        // Project corners1 onto axis
        let proj1 = corners1.map { dot($0, axis) }
        let min1 = proj1.min()!
        let max1 = proj1.max()!
        
        // Project corners2 onto axis
        let proj2 = corners2.map { dot($0, axis) }
        let min2 = proj2.min()!
        let max2 = proj2.max()!
        
        // Check for gap (with minimum distance)
        if max1 + minDistance < min2 || max2 + minDistance < min1 {
            // Found separating axis - no overlap!
            return false
        }
    }
    
    // No separating axis found - boxes overlap!
    return true
}

/// Check if a furniture item overlaps with any existing furniture
func checkForOverlaps(
    newItem: PlacedFurniture,
    existingItems: [PlacedFurniture],
    minDistance: Float = 0.3
) -> Bool {
    
    let newBounds = getBounds2D(for: newItem)
    
    for existing in existingItems {
        let existingBounds = getBounds2D(for: existing)
        
        if checkOverlap(bounds1: newBounds, bounds2: existingBounds, minDistance: minDistance) {
            print("  ❌ \(newItem.category) overlaps with \(existing.category)")
            return true
        }
    }
    
    return false
}

/// Remove overlapping furniture from layout
public func removeOverlappingFurniture(
    layout: [PlacedFurniture],
    minDistance: Float = 0.3
) -> [PlacedFurniture] {
    
    print("\n🔍 Checking for overlapping furniture...")
    
    var validItems: [PlacedFurniture] = []
    var removedItems: [String] = []
    
    for item in layout {
        if checkForOverlaps(newItem: item, existingItems: validItems, minDistance: minDistance) {
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
    existingItems: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    maxAttempts: Int = 50
) -> PlacedFurniture? {
    
    let searchRadius: Float = 0.5
    let angleStep: Float = 30.0  // degrees
    let radiusStep: Float = 0.3
    
    // Try positions in a spiral pattern
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
            
            // Check if valid
            if isPointInPolygonWithMargin(point: newPos2D, polygon: polygon, margin: 0.4) &&
               !checkForOverlaps(newItem: testItem, existingItems: existingItems, minDistance: 0.3) {
                print("  ✅ Found valid position for \(item.category) at offset \(offset)")
                return testItem
            }
        }
    }
    
    print("  ❌ Could not find valid position for \(item.category)")
    return nil
}

/// Smart furniture placement with collision avoidance
public func placeWithCollisionAvoidance(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>]
) -> [PlacedFurniture] {
    
    print("\n🎯 Placing furniture with collision avoidance...")
    
    var validItems: [PlacedFurniture] = []
    
    // Sort by priority (larger items first)
    let priorityOrder = ["Bed", "Wardrobe", "Sofa", "Study Desk", "Bookshelf", "Table", "Office Chair", "Lamp", "Pot"]
    let sortedLayout = layout.sorted { item1, item2 in
        let priority1 = priorityOrder.firstIndex(of: item1.category) ?? 999
        let priority2 = priorityOrder.firstIndex(of: item2.category) ?? 999
        return priority1 < priority2
    }
    
    for item in sortedLayout {
        // Check if item overlaps with existing
        if checkForOverlaps(newItem: item, existingItems: validItems, minDistance: 0.3) {
            print("  ⚠️ \(item.category) overlaps, finding new position...")
            
            // Try to find non-overlapping position
            if let fixedItem = findNonOverlappingPosition(
                for: item,
                existingItems: validItems,
                polygon: polygon
            ) {
                validItems.append(fixedItem)
                print("  ✅ \(item.category) relocated successfully")
            } else {
                print("  🗑️ \(item.category) could not be placed - removing")
            }
        } else {
            validItems.append(item)
            print("  ✅ \(item.category) placed without collision")
        }
    }
    
    print("\n✅ Collision avoidance complete: \(validItems.count)/\(layout.count) items placed")
    return validItems
}
