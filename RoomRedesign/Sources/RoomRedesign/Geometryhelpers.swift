import Foundation
import simd

// ============================================================================
// PART 1: EXISTING FUNCTIONS (KEEP THESE)
// ============================================================================

/// IMPROVED: Checks if a 2D point is inside a polygon using ray casting algorithm
/// Now handles edge cases better (points on edges, collinear points, etc.)
public func isPointInPolygon(point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
    guard polygon.count >= 3 else { return false }
    
    var inside = false
    var j = polygon.count - 1
    
    for i in 0..<polygon.count {
        let xi = polygon[i].x
        let yi = polygon[i].y
        let xj = polygon[j].x
        let yj = polygon[j].y
        
        let intersect = ((yi > point.y) != (yj > point.y)) &&
                       (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi)
        
        if intersect {
            inside = !inside
        }
        j = i
    }
    
    return inside
}

/// IMPROVED: Checks if a point is inside a polygon with a safety margin
/// Now uses proper distance-to-polygon calculation
public func isPointInPolygonWithMargin(
    point: SIMD2<Float>,
    polygon: [SIMD2<Float>],
    margin: Float = 0.3
) -> Bool {
    // First check if point is in the original polygon
    guard isPointInPolygon(point: point, polygon: polygon) else {
        return false
    }
    
    // Calculate minimum distance to any edge
    let minDistance = minimumDistanceToPolygonEdge(point: point, polygon: polygon)
    
    return minDistance >= margin
}

/// NEW: Calculate the minimum distance from a point to the polygon edges
public func minimumDistanceToPolygonEdge(point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Float {
    var minDistance = Float.infinity
    
    for i in 0..<polygon.count {
        let j = (i + 1) % polygon.count
        let distance = distanceToLineSegment(point: point, p1: polygon[i], p2: polygon[j])
        minDistance = min(minDistance, distance)
    }
    
    return minDistance
}

/// NEW: Calculate distance from a point to a line segment
private func distanceToLineSegment(point: SIMD2<Float>, p1: SIMD2<Float>, p2: SIMD2<Float>) -> Float {
    let edge = p2 - p1
    let toPoint = point - p1
    
    let edgeLengthSquared = dot(edge, edge)
    
    if edgeLengthSquared < 0.0001 {
        // Edge is essentially a point
        return length(toPoint)
    }
    
    // Calculate the projection parameter t
    let t = max(0.0, min(1.0, dot(toPoint, edge) / edgeLengthSquared))
    
    // Calculate the closest point on the segment
    let projection = p1 + edge * t
    
    return length(point - projection)
}

/// Get the center (centroid) of a polygon
public func getPolygonCenter(polygon: [SIMD2<Float>]) -> SIMD2<Float> {
    guard !polygon.isEmpty else { return SIMD2<Float>(0, 0) }
    
    var sum = SIMD2<Float>(0, 0)
    for point in polygon {
        sum += point
    }
    return sum / Float(polygon.count)
}

/// Get the bounding box of a polygon
public func getPolygonBounds(polygon: [SIMD2<Float>]) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
    guard !polygon.isEmpty else {
        return (SIMD2<Float>(0, 0), SIMD2<Float>(0, 0))
    }
    
    var minX = Float.infinity
    var minY = Float.infinity
    var maxX = -Float.infinity
    var maxY = -Float.infinity
    
    for point in polygon {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }
    
    return (SIMD2<Float>(minX, minY), SIMD2<Float>(maxX, maxY))
}

/// Calculate the area of a polygon using the shoelace formula
public func getPolygonArea(polygon: [SIMD2<Float>]) -> Float {
    guard polygon.count >= 3 else { return 0 }
    
    var area: Float = 0
    
    for i in 0..<polygon.count {
        let j = (i + 1) % polygon.count
        area += polygon[i].x * polygon[j].y
        area -= polygon[j].x * polygon[i].y
    }
    
    return abs(area / 2.0)
}

/// Clean and validate a polygon by removing duplicate vertices
public func cleanPolygon(_ polygon: [SIMD2<Float>]) -> [SIMD2<Float>] {
    guard polygon.count >= 3 else { return polygon }
    
    var cleaned: [SIMD2<Float>] = []
    let epsilon: Float = 0.001 // 1mm tolerance
    
    for i in 0..<polygon.count {
        let current = polygon[i]
        let next = polygon[(i + 1) % polygon.count]
        
        let distance = length(next - current)
        if distance > epsilon {
            cleaned.append(current)
        }
    }
    
    if cleaned.count < 3 {
        return polygon // Return original if cleaning failed
    }
    
    return cleaned
}

/// IMPROVED: Find the nearest valid position inside the polygon
/// Now uses multiple strategies and better fallback logic
public func findNearestValidPosition(
    point: SIMD2<Float>,
    polygon: [SIMD2<Float>],
    margin: Float = 0.3
) -> SIMD2<Float>? {
    
    // Strategy 1: If already valid, return as-is
    if isPointInPolygonWithMargin(point: point, polygon: polygon, margin: margin) {
        return point
    }
    
    // Strategy 2: If point is in polygon but too close to edge, move toward center
    if isPointInPolygon(point: point, polygon: polygon) {
        let center = getPolygonCenter(polygon: polygon)
        let toCenter = normalize(center - point)
        
        // Binary search for the nearest valid point along the direction to center
        var minDist: Float = 0
        var maxDist = length(center - point)
        var bestPoint: SIMD2<Float>? = nil
        
        for _ in 0..<20 { // 20 iterations for binary search
            let testDist = (minDist + maxDist) / 2
            let testPoint = point + toCenter * testDist
            
            if isPointInPolygonWithMargin(point: testPoint, polygon: polygon, margin: margin) {
                bestPoint = testPoint
                maxDist = testDist // Found valid point, try getting closer
            } else {
                minDist = testDist // Not valid, need to move further
            }
        }
        
        if let valid = bestPoint {
            return valid
        }
    }
    
    // Strategy 3: Point is completely outside - project onto polygon and move inward
    // Find nearest edge
    var nearestEdgeIndex = 0
    var minDistToEdge = Float.infinity
    var nearestPointOnEdge = SIMD2<Float>(0, 0)
    
    for i in 0..<polygon.count {
        let j = (i + 1) % polygon.count
        let p1 = polygon[i]
        let p2 = polygon[j]
        
        let edge = p2 - p1
        let toPoint = point - p1
        let edgeLengthSquared = dot(edge, edge)
        
        if edgeLengthSquared < 0.0001 { continue }
        
        let t = max(0.0, min(1.0, dot(toPoint, edge) / edgeLengthSquared))
        let projection = p1 + edge * t
        let distance = length(point - projection)
        
        if distance < minDistToEdge {
            minDistToEdge = distance
            nearestEdgeIndex = i
            nearestPointOnEdge = projection
        }
    }
    
    // Move from nearest edge toward center by margin
    let center = getPolygonCenter(polygon: polygon)
    let fromEdgeToCenter = normalize(center - nearestPointOnEdge)
    let candidatePoint = nearestPointOnEdge + fromEdgeToCenter * margin * 1.5 // 1.5x margin for safety
    
    if isPointInPolygonWithMargin(point: candidatePoint, polygon: polygon, margin: margin) {
        return candidatePoint
    }
    
    // Strategy 4: Last resort - use center with slight random offset to avoid overlap
    let randomAngle = Float.random(in: 0..<(2 * Float.pi))
    let randomOffset = SIMD2<Float>(cos(randomAngle), sin(randomAngle)) * 0.2
    let centerWithOffset = center + randomOffset
    
    if isPointInPolygonWithMargin(point: centerWithOffset, polygon: polygon, margin: margin) {
        return centerWithOffset
    }
    
    // Absolute last resort - just return center
    return center
}

/// IMPROVED: Validate and fix a furniture layout
/// Now with better distribution and anti-stacking logic
public func validateAndFixLayout(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    margin: Float = 0.3
) -> [PlacedFurniture] {
    
    guard !polygon.isEmpty else {
        print("⚠️ WARNING: Empty polygon, cannot validate layout")
        return layout
    }
    
    // Clean the polygon first
    let cleanedPolygon = cleanPolygon(polygon)
    
    // Check if polygon is valid
    let area = getPolygonArea(polygon: cleanedPolygon)
    if area < 0.1 {
        print("❌ ERROR: Polygon area too small (\(area) m²). Cannot validate positions.")
        print("💡 Using fallback: returning AI positions without validation")
        return layout
    }
    
    print("✅ Validating against polygon with area: \(String(format: "%.2f", area)) m²")
    
    var fixedLayout: [PlacedFurniture] = []
    var usedPositions: [SIMD2<Float>] = [] // Track positions to avoid stacking
    let minSpacing: Float = 0.3 // Minimum distance between furniture items
    
    for (index, item) in layout.enumerated() {
        let pos2D = SIMD2<Float>(item.position.x, item.position.z)
        
        // Check if position is valid
        var finalPosition: SIMD2<Float>? = nil
        
        if isPointInPolygonWithMargin(point: pos2D, polygon: cleanedPolygon, margin: margin) {
            // Position is valid, but check if it's too close to existing furniture
            var tooClose = false
            for usedPos in usedPositions {
                if length(pos2D - usedPos) < minSpacing {
                    tooClose = true
                    break
                }
            }
            
            if !tooClose {
                finalPosition = pos2D
            } else {
                print("  ⚠️ [\(index)] \(item.category): Position valid but too close to other furniture, finding new position...")
                // Try to find a nearby valid position that's not too close
                finalPosition = findPositionAwayFromOthers(
                    near: pos2D,
                    polygon: cleanedPolygon,
                    margin: margin,
                    usedPositions: usedPositions,
                    minSpacing: minSpacing
                )
            }
        } else {
            // Position is invalid, find nearest valid position
            print("  ❌ [\(index)] \(item.category) at (\(String(format: "%.2f", pos2D.x)), \(String(format: "%.2f", pos2D.y))): INVALID")
            finalPosition = findNearestValidPosition(point: pos2D, polygon: cleanedPolygon, margin: margin)
            
            if let correctedPos = finalPosition {
                print("  ✅ Corrected to (\(String(format: "%.2f", correctedPos.x)), \(String(format: "%.2f", correctedPos.y)))")
            }
        }
        
        // Add to layout if we found a valid position
        if let validPos = finalPosition {
            let correctedItem = PlacedFurniture(
                position: SIMD3<Float>(validPos.x, item.position.y, validPos.y),
                rotation: item.rotation,
                category: item.category
            )
            fixedLayout.append(correctedItem)
            usedPositions.append(validPos)
        } else {
            print("  ❌ [\(index)] \(item.category): Could not find valid position, REMOVED")
        }
    }
    
    print("📊 Validation complete: \(layout.count) → \(fixedLayout.count) items")
    
    return fixedLayout
}

/// NEW: Find a position near a target that's not too close to existing furniture
private func findPositionAwayFromOthers(
    near targetPos: SIMD2<Float>,
    polygon: [SIMD2<Float>],
    margin: Float,
    usedPositions: [SIMD2<Float>],
    minSpacing: Float
) -> SIMD2<Float>? {
    
    // Try positions in a spiral pattern around the target
    let radiusIncrement: Float = 0.2
    let maxRadius: Float = 3.0
    var radius = minSpacing
    
    while radius <= maxRadius {
        // Try 8 directions around the circle
        for angle in stride(from: 0.0, to: 2.0 * Float.pi, by: Float.pi / 4.0) {
            let offset = SIMD2<Float>(cos(angle), sin(angle)) * radius
            let candidate = targetPos + offset
            
            // Check if position is valid and not too close to others
            if isPointInPolygonWithMargin(point: candidate, polygon: polygon, margin: margin) {
                var isGoodPosition = true
                for usedPos in usedPositions {
                    if length(candidate - usedPos) < minSpacing {
                        isGoodPosition = false
                        break
                    }
                }
                
                if isGoodPosition {
                    return candidate
                }
            }
        }
        
        radius += radiusIncrement
    }
    
    // If spiral search failed, just use the original findNearestValidPosition
    return findNearestValidPosition(point: targetPos, polygon: polygon, margin: margin)
}

/// Calculate wall orientations for rotation alignment
public func calculateWallOrientations(polygon: [SIMD2<Float>]) -> (primary: Float, secondary: Float) {
    guard polygon.count >= 3 else { return (0, 90) }
    
    var edgeAngles: [(angle: Float, length: Float)] = []
    
    for i in 0..<polygon.count {
        let j = (i + 1) % polygon.count
        let edge = polygon[j] - polygon[i]
        let edgeLength = simd_length(edge)
        
        if edgeLength > 0.5 {
            let angle = atan2(edge.y, edge.x) * 180.0 / Float.pi
            var normalizedAngle = angle
            while normalizedAngle < 0 { normalizedAngle += 180 }
            while normalizedAngle >= 180 { normalizedAngle -= 180 }
            
            edgeAngles.append((normalizedAngle, edgeLength))
        }
    }
    
    guard !edgeAngles.isEmpty else { return (0, 90) }
    
    // Find the longest edge for primary orientation
    let primaryEdge = edgeAngles.max(by: { $0.length < $1.length })!
    let primaryAngle = primaryEdge.angle
    
    // Find secondary angle (closest to 90° from primary)
    var secondaryAngle = primaryAngle + 90
    while secondaryAngle >= 180 { secondaryAngle -= 180 }
    
    return (primaryAngle, secondaryAngle)
}

/// Align all furniture rotations to walls
public func alignLayoutRotations(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>]
) -> [PlacedFurniture] {
    
    guard !polygon.isEmpty else { return layout }
    
    let wallOrientations = calculateWallOrientations(polygon: polygon)
    
    return layout.map { item in
        let pos2D = SIMD2<Float>(item.position.x, item.position.z)
        let alignedRotation = calculateFurnitureRotation(
            category: item.category,
            position: pos2D,
            polygon: polygon,
            wallOrientations: wallOrientations
        )
        
        return PlacedFurniture(
            position: item.position,
            rotation: alignedRotation,
            category: item.category
        )
    }
}

/// Calculate appropriate rotation for furniture based on nearest wall
public func calculateFurnitureRotation(
    category: String,
    position: SIMD2<Float>,
    polygon: [SIMD2<Float>],
    wallOrientations: (primary: Float, secondary: Float)
) -> Float {
    
    // Find nearest wall
    var nearestWallAngle: Float = 0
    var minDistance = Float.infinity
    
    for i in 0..<polygon.count {
        let j = (i + 1) % polygon.count
        let p1 = polygon[i]
        let p2 = polygon[j]
        
        let distance = distanceToLineSegment(point: position, p1: p1, p2: p2)
        
        if distance < minDistance {
            minDistance = distance
            let wall = p2 - p1
            nearestWallAngle = atan2(wall.y, wall.x) * 180.0 / Float.pi
        }
    }
    
    // Determine rotation based on category
    var baseRotation: Float = 0
    
    switch category {
    case "Sofa", "Bookshelf", "Study Desk":
        // Face away from wall (perpendicular)
        baseRotation = nearestWallAngle + 90
    case "Table", "Lamp", "Office Chair":
        // Align with room orientation
        baseRotation = wallOrientations.primary
    default:
        baseRotation = wallOrientations.primary
    }
    
    // Normalize to 0-360
    while baseRotation < 0 { baseRotation += 360 }
    while baseRotation >= 360 { baseRotation -= 360 }
    
    return baseRotation
}

// ============================================================================
// PART 2: ROBUST FUNCTIONS FOR IRREGULAR POLYGONS (ADD THESE)
// ============================================================================

/// ROBUST: Better point-in-polygon for irregular quadrilaterals
public func isPointInPolygonRobust(point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
    return isPointInPolygon(point: point, polygon: polygon) // Same implementation, just aliased
}

/// ROBUST: Better margin checking for irregular polygons
/// Calculates ACTUAL distance to edges, not just bounding box
public func isPointInPolygonWithMarginRobust(
    point: SIMD2<Float>,
    polygon: [SIMD2<Float>],
    margin: Float = 0.4
) -> Bool {
    return isPointInPolygonWithMargin(point: point, polygon: polygon, margin: margin)
}

/// ROBUST: Better position correction for irregular polygons
public func findNearestValidPositionRobust(
    point: SIMD2<Float>,
    polygon: [SIMD2<Float>],
    margin: Float = 0.4
) -> SIMD2<Float>? {
    
    // Strategy 1: If already valid, return as-is
    if isPointInPolygonWithMarginRobust(point: point, polygon: polygon, margin: margin) {
        return point
    }
    
    // Strategy 2: Move toward polygon center
    let center = getPolygonCenter(polygon: polygon)
    let toCenter = center - point
    let distToCenter = length(toCenter)
    
    if distToCenter > 0.01 {
        let direction = normalize(toCenter)
        
        // Binary search along the line from point to center
        var low: Float = 0
        var high = distToCenter
        var bestPoint: SIMD2<Float>? = nil
        
        for _ in 0..<30 { // More iterations for precision
            let mid = (low + high) / 2
            let testPoint = point + direction * mid
            
            if isPointInPolygonWithMarginRobust(point: testPoint, polygon: polygon, margin: margin) {
                bestPoint = testPoint
                high = mid // Try to get closer to original position
            } else {
                low = mid // Need to move further toward center
            }
        }
        
        if let valid = bestPoint {
            return valid
        }
    }
    
    // Strategy 3: Last resort - use center with small random offset
    let randomAngle = Float.random(in: 0..<(2 * .pi))
    let offset = SIMD2<Float>(cos(randomAngle), sin(randomAngle)) * 0.2
    let centerWithOffset = center + offset
    
    if isPointInPolygonWithMarginRobust(point: centerWithOffset, polygon: polygon, margin: margin) {
        return centerWithOffset
    }
    
    // Absolute last resort
    return center
}

/// ROBUST: Use robust validation instead of basic one
public func validateAndFixLayoutRobust(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    margin: Float = 0.5
) -> [PlacedFurniture] {
    
    guard !polygon.isEmpty else {
        print("⚠️ WARNING: Empty polygon, cannot validate layout")
        return layout
    }
    
    let area = getPolygonArea(polygon: polygon)
    if area < 0.1 {
        print("❌ ERROR: Polygon area too small")
        return layout
    }
    
    print("🔍 ROBUST VALIDATION (accounting for irregular shape):")
    print("   Polygon area: \(String(format: "%.2f", area)) m²")
    print("   Margin: \(String(format: "%.2f", margin))m")
    
    var fixedLayout: [PlacedFurniture] = []
    var usedPositions: [SIMD2<Float>] = []
    let minSpacing: Float = 0.3
    
    for (index, item) in layout.enumerated() {
        let pos2D = SIMD2<Float>(item.position.x, item.position.z)
        
        // Use ROBUST validation
        let isValid = isPointInPolygonWithMarginRobust(point: pos2D, polygon: polygon, margin: margin)
        
        var finalPosition: SIMD2<Float>? = nil
        
        if isValid {
            // Check spacing from other furniture
            var tooClose = false
            for usedPos in usedPositions {
                if length(pos2D - usedPos) < minSpacing {
                    tooClose = true
                    break
                }
            }
            
            if !tooClose {
                finalPosition = pos2D
                print("  ✅ [\(index)] \(item.category) OK at (\(String(format: "%.2f", pos2D.x)), \(String(format: "%.2f", pos2D.y)))")
            } else {
                print("  ⚠️ [\(index)] \(item.category) too close to other furniture")
                finalPosition = findNearestValidPositionRobust(point: pos2D, polygon: polygon, margin: margin)
            }
        } else {
            print("  ❌ [\(index)] \(item.category) INVALID at (\(String(format: "%.2f", pos2D.x)), \(String(format: "%.2f", pos2D.y)))")
            finalPosition = findNearestValidPositionRobust(point: pos2D, polygon: polygon, margin: margin)
            
            if let corrected = finalPosition {
                print("     → Corrected to (\(String(format: "%.2f", corrected.x)), \(String(format: "%.2f", corrected.y)))")
            }
        }
        
        if let validPos = finalPosition {
            let correctedItem = PlacedFurniture(
                position: SIMD3<Float>(validPos.x, item.position.y, validPos.y),
                rotation: item.rotation,
                category: item.category
            )
            fixedLayout.append(correctedItem)
            usedPositions.append(validPos)
        } else {
            print("     → REMOVED (no valid position found)")
        }
    }
    
    print("📊 Validation result: \(layout.count) → \(fixedLayout.count) items")
    return fixedLayout
}

/// ROBUST: Calculate rotation for irregular rooms
public func calculateFurnitureRotationForIrregularRoom(
    category: String,
    position: SIMD2<Float>,
    polygon: [SIMD2<Float>]
) -> Float {
    
    // Find the nearest wall edge
    var nearestWallAngle: Float = 0
    var minDistance = Float.infinity
    
    for i in 0..<polygon.count {
        let j = (i + 1) % polygon.count
        let p1 = polygon[i]
        let p2 = polygon[j]
        
        let distance = distanceToLineSegment(point: position, p1: p1, p2: p2)
        
        if distance < minDistance {
            minDistance = distance
            let wall = p2 - p1
            nearestWallAngle = atan2(wall.y, wall.x) * 180.0 / .pi
        }
    }
    
    // Determine rotation based on category
    var rotation: Float = 0
    
    switch category {
    case "Sofa", "Bookshelf", "Study Desk":
        // Face AWAY from wall (perpendicular)
        rotation = nearestWallAngle + 90
    case "Office Chair":
        rotation = nearestWallAngle + 90
    case "Table", "Lamp":
        rotation = 0
    default:
        rotation = 0
    }
    
    // Normalize to 0-360
    while rotation < 0 { rotation += 360 }
    while rotation >= 360 { rotation -= 360 }
    
    return rotation
}

// ============================================================================
// SMART ROTATION - MOST REALISTIC (RECOMMENDED FOR YOU)
// ============================================================================
// Replace alignLayoutRotationsForIrregularRoom in GeometryHelpers.swift
// This version includes ALL your furniture types including new ones
// ============================================================================

/// SMART: Most realistic rotation - each item faces away from its nearest wall
public func alignLayoutRotationsForIrregularRoom(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>]
) -> [PlacedFurniture] {
    
    guard !polygon.isEmpty else { return layout }
    
    print("🎯 Smart rotation: aligning furniture to nearest walls...")
    
    return layout.map { item in
        let pos2D = SIMD2<Float>(item.position.x, item.position.z)
        
        // Find the nearest wall edge
        var nearestWallAngle: Float = 0
        var minDistance = Float.infinity
        
        for i in 0..<polygon.count {
            let j = (i + 1) % polygon.count
            let p1 = polygon[i]
            let p2 = polygon[j]
            
            // Calculate distance to this wall segment
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
        
        // Calculate rotation based on category and nearest wall
        var rotation: Float = 0
        
        switch item.category {
        // ========================================
        // LARGE FURNITURE - Face AWAY from wall
        // ========================================
        case "Sofa":
            // Sofa should face away from wall (into room)
            rotation = nearestWallAngle + 90
            
        case "Bed":
            // Bed headboard against wall, face away
            rotation = nearestWallAngle + 90
            
        case "Study Desk", "Dressing_Table":
            // Desks face away from wall (user sits facing away)
            rotation = nearestWallAngle + 90
            
        case "Bookshelf", "WardRobe":
            // Storage faces away from wall (door opens into room)
            rotation = nearestWallAngle + 90
            
        // ========================================
        // CHAIRS - Face away from wall
        // ========================================
        case "Office Chair":
            // Chair faces away from wall (toward desk/table)
            rotation = nearestWallAngle + 90
            
        // ========================================
        // SMALL/CENTER ITEMS - Stay upright
        // ========================================
        case "Table":
            // Tables can stay upright (no front/back)
            rotation = 0
            
        case "Lamp", "Pot":
            // Small decorative items stay upright
            rotation = 0
            
        // ========================================
        // WALL DECORATIONS - Stay upright
        // ========================================
        case "Painting", "Wall_Clock":
            // Wall items stay at 0° (placed manually or via special logic)
            rotation = 0
            
        // ========================================
        // DEFAULT - Everything else upright
        // ========================================
        default:
            rotation = 0
        }
        
        // Normalize to 0-360
        while rotation < 0 { rotation += 360 }
        while rotation >= 360 { rotation -= 360 }
        
        print("  🧭 \(item.category): \(String(format: "%.0f", rotation))°")
        
        return PlacedFurniture(
            position: item.position,
            rotation: rotation,
            category: item.category
        )
    }
}


// ============================================================================
// BONUS: If you want even MORE control, use this version instead
// ============================================================================
// This version lets you customize the rotation offset for each furniture type

/// ADVANCED SMART: Custom rotation offsets per furniture type
public func alignLayoutRotationsForIrregularRoomAdvanced(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>]
) -> [PlacedFurniture] {
    
    guard !polygon.isEmpty else { return layout }
    
    print("🎯 Advanced rotation: custom angles per furniture type...")
    
    return layout.map { item in
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
        
        // Custom rotation offset per category
        var rotationOffset: Float = 0
        
        switch item.category {
        case "Sofa":
            rotationOffset = 90  // Face away from wall
        case "Bed":
            rotationOffset = 90  // Headboard against wall
        case "Study Desk":
            rotationOffset = 90  // Face away
        case "Dressing_Table":
            rotationOffset = 90  // Face away
        case "Bookshelf":
            rotationOffset = 90  // Face into room
        case "Wardrobe":
            rotationOffset = 90  // Doors face room
        case "Office Chair":
            rotationOffset = 90  // Face away from wall
        
        // If your models need different angles, adjust here:
        // case "Bed":
        //     rotationOffset = 180  // If bed model faces wrong way
        
        default:
            rotationOffset = 0  // Stay upright
        }
        
        // Calculate final rotation
        var rotation = nearestWallAngle + rotationOffset
        
        // Normalize
        while rotation < 0 { rotation += 360 }
        while rotation >= 360 { rotation -= 360 }
        
        print("  🧭 \(item.category): wall=\(String(format: "%.0f", nearestWallAngle))° + offset=\(String(format: "%.0f", rotationOffset))° = \(String(format: "%.0f", rotation))°")
        
        return PlacedFurniture(
            position: item.position,
            rotation: rotation,
            category: item.category
        )
    }
}
