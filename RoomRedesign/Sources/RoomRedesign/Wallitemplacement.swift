import Foundation
import simd
import RealityKit

// ============================================================================
// WALL ITEM PLACEMENT SYSTEM
// ============================================================================

// Helper to check if item is a wall decoration
func isWallItem(_ category: String) -> Bool {
    return category == "Painting" ||
           category == "Wall_Clock" ||
           category == "Wall Clock"
}

/// Find walls in the room and place wall items (paintings, clocks) on them
func placeWallItems(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    floorHeight: Float
) -> [PlacedFurniture] {
    
    print("\n🖼️ Placing wall items (paintings, clocks)...")
    
    var result = layout.filter { !isWallItem($0.category) }
    let wallItems = layout.filter { isWallItem($0.category) }
    
    guard !wallItems.isEmpty else {
        print("  ℹ️ No wall items to place")
        return layout
    }
    
    print("  📋 Found \(wallItems.count) wall items: \(wallItems.map { $0.category }.joined(separator: ", "))")
    
    // Get wall segments
    let walls = extractWallSegments(from: polygon)
    print("  🧱 Found \(walls.count) wall segments")
    
    guard !walls.isEmpty else {
        print("  ❌ No valid walls found!")
        return layout
    }
    
    // Place each wall item
    for wallItem in wallItems {
        if let placed = placeItemOnWall(
            item: wallItem,
            walls: walls,
            floorHeight: floorHeight,
            existingItems: result
        ) {
            result.append(placed)
            print("  ✅ Placed \(wallItem.category)")
        } else {
            print("  ❌ Could not place \(wallItem.category)")
        }
    }
    
    print("\n✅ Wall item placement complete: \(result.count - (layout.count - wallItems.count)) items placed")
    return result
}

/// Represents a wall segment
struct WallSegment {
    let start: SIMD2<Float>
    let end: SIMD2<Float>
    let midpoint: SIMD2<Float>
    let length: Float
    let normal: SIMD2<Float>
    let angle: Float
}

func extractWallSegments(from polygon: [SIMD2<Float>]) -> [WallSegment] {
    
    guard polygon.count >= 3 else { return [] }
    
    var walls: [WallSegment] = []
    let center = getPolygonCenter(polygon: polygon)
    
    for i in 0..<polygon.count {
        let next = (i + 1) % polygon.count
        let start = polygon[i]
        let end = polygon[next]
        
        let edge = end - start
        let length = simd_length(edge)
        
        // Skip very short edges
        guard length > 0.5 else { continue }
        
        let midpoint = (start + end) / 2
        
        // Calculate normal pointing inward
        let perpendicular = SIMD2(-edge.y, edge.x)
        let normalized = normalize(perpendicular)
        
        // Check if normal points toward center
        let toCenter = center - midpoint
        let normal = dot(normalized, toCenter) > 0 ? normalized : -normalized
        
        // Calculate rotation angle for items on this wall
        let wallDirection = end - start
        let angle = atan2(wallDirection.y, wallDirection.x) * 180.0 / .pi
        
        walls.append(WallSegment(
            start: start,
            end: end,
            midpoint: midpoint,
            length: length,
            normal: normal,
            angle: angle
        ))
    }
    
    return walls
}

/// Get default height offset for wall items
func getWallItemHeight(category: String) -> Float {
    switch category {
    case "Painting":
        return 1.5  // Eye level
    case "Wall_Clock", "Wall Clock":
        return 2.0  // Above eye level
    default:
        return 1.5
    }
}

/// Place a wall item on the best available wall
func placeItemOnWall(
    item: PlacedFurniture,
    walls: [WallSegment],
    floorHeight: Float,
    existingItems: [PlacedFurniture]
) -> PlacedFurniture? {
    
    let heightOffset = getWallItemHeight(category: item.category)
    let targetHeight = floorHeight + heightOffset
    let minWallSpacing: Float = 1.0  // Minimum distance between wall items
    
    // Try each wall
    for wall in walls {
        // Check if this wall is long enough
        guard wall.length >= 1.0 else { continue }
        
        // Calculate position on wall
        // Move item slightly away from wall (so it doesn't clip through)
        let wallOffset: Float = 0.05
        let position2D = wall.midpoint + wall.normal * wallOffset
        
        let position3D = SIMD3<Float>(
            position2D.x,
            targetHeight,
            position2D.y
        )
        
        // Calculate rotation to face into room
        let rotation = wall.angle + 90.0  // Face perpendicular to wall
        
        let placedItem = PlacedFurniture(
            position: position3D,
            rotation: rotation,
            category: item.category
        )
        
        // Check if this position conflicts with other wall items
        var hasConflict = false
        for existing in existingItems where isWallItem(existing.category) {
            let distance = simd_length(
                SIMD2(existing.position.x, existing.position.z) -
                SIMD2(position3D.x, position3D.z)
            )
            
            if distance < minWallSpacing {
                hasConflict = true
                break
            }
        }
        
        if !hasConflict {
            print("    ✅ Found spot on wall (length: \(String(format: "%.2f", wall.length))m)")
            return placedItem
        }
    }
    
    print("    ❌ No suitable wall found")
    return nil
}

/// Alternative: Place wall items distributed along walls
public func distributeWallItemsEvenly(
    wallItems: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    floorHeight: Float
) -> [PlacedFurniture] {
    
    print("\n🎨 Distributing \(wallItems.count) wall items evenly...")
    
    let walls = extractWallSegments(from: polygon)
    guard !walls.isEmpty else {
        print("  ❌ No walls found")
        return []
    }
    
    // Sort walls by length (longest first)
    let sortedWalls = walls.sorted { $0.length > $1.length }
    
    var result: [PlacedFurniture] = []
    var wallIndex = 0
    
    for item in wallItems {
        guard wallIndex < sortedWalls.count else {
            print("  ⚠️ Ran out of walls for \(item.category)")
            break
        }
        
        let wall = sortedWalls[wallIndex]
        let heightOffset = getWallItemHeight(category: item.category)
        let targetHeight = floorHeight + heightOffset
        let wallOffset: Float = 0.05
        
        // Place at 1/3 or 2/3 along wall for variety
        let t: Float = (wallIndex % 2 == 0) ? 0.33 : 0.67
        let positionOnWall = wall.start + (wall.end - wall.start) * t
        let position2D = positionOnWall + wall.normal * wallOffset
        
        let position3D = SIMD3<Float>(
            position2D.x,
            targetHeight,
            position2D.y
        )
        
        let rotation = wall.angle + 90.0
        
        let placedItem = PlacedFurniture(
            position: position3D,
            rotation: rotation,
            category: item.category
        )
        
        result.append(placedItem)
        print("  ✅ Placed \(item.category) on wall \(wallIndex + 1)")
        
        wallIndex += 1
    }
    
    return result
}

// ============================================================================
// SMART WALL ITEM PLACEMENT (RECOMMENDED)
// ============================================================================

/// Intelligently place wall items based on room layout
public func smartPlaceWallItems(
    floorItems: [PlacedFurniture],
    wallItems: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    floorHeight: Float
) -> [PlacedFurniture] {
    
    print("\n🧠 Smart wall item placement...")
    
    let walls = extractWallSegments(from: polygon)
    guard !walls.isEmpty else { return floorItems }
    
    var result = floorItems
    
    for wallItem in wallItems {
        // Find walls that are clear of furniture
        var bestWall: WallSegment? = nil
        var maxClearance: Float = 0
        
        for wall in walls where wall.length >= 1.0 {
            // Check how much clear space this wall has
            let clearance = calculateWallClearance(
                wall: wall,
                floorItems: floorItems,
                existingWallItems: result.filter { isWallItem($0.category) }
            )
            
            if clearance > maxClearance {
                maxClearance = clearance
                bestWall = wall
            }
        }
        
        guard let wall = bestWall, maxClearance > 0.5 else {
            print("  ❌ No suitable wall for \(wallItem.category)")
            continue
        }
        
        // Place on best wall
        let heightOffset = getWallItemHeight(category: wallItem.category)
        let targetHeight = floorHeight + heightOffset
        let wallOffset: Float = 0.05
        let position2D = wall.midpoint + wall.normal * wallOffset
        
        let position3D = SIMD3<Float>(
            position2D.x,
            targetHeight,
            position2D.y
        )
        
        let rotation = wall.angle + 90.0
        
        let placedItem = PlacedFurniture(
            position: position3D,
            rotation: rotation,
            category: wallItem.category
        )
        
        result.append(placedItem)
        print("  ✅ Placed \(wallItem.category) on wall with \(String(format: "%.2f", maxClearance))m clearance")
    }
    
    return result
}

/// Calculate how much clear space a wall has
func calculateWallClearance(
    wall: WallSegment,
    floorItems: [PlacedFurniture],
    existingWallItems: [PlacedFurniture]
) -> Float {
    
    let wallMidpoint = wall.midpoint
    var minDistance: Float = .infinity
    
    // Check distance to floor furniture
    for item in floorItems {
        let itemPos2D = SIMD2(item.position.x, item.position.z)
        let distance = simd_length(itemPos2D - wallMidpoint)
        minDistance = min(minDistance, distance)
    }
    
    // Check distance to other wall items
    for item in existingWallItems {
        let itemPos2D = SIMD2(item.position.x, item.position.z)
        let distance = simd_length(itemPos2D - wallMidpoint)
        minDistance = min(minDistance, distance)
    }
    
    return minDistance
}
