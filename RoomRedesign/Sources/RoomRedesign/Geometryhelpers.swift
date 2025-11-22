import Foundation
import simd
import ModelIO
import RealityKit

// ============================================================================
// BOUNDING BOX STRUCTURE
// ============================================================================

public struct BoundingBox {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>
    
    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }
    
    // NEW: Initialize from RealityKit's BoundingBox
    public init(from rkBounds: RealityFoundation.BoundingBox) {
        self.min = rkBounds.min
        self.max = rkBounds.max
    }
    
    // NEW: Computed properties for compatibility
    public var center: SIMD3<Float> {
        return (min + max) / 2.0
    }
    
    public var extents: SIMD3<Float> {
        return max - min
    }
    
    // NEW: Union method to combine two bounding boxes
    public func union(_ other: BoundingBox) -> BoundingBox {
        return BoundingBox(
            min: SIMD3<Float>(
                Swift.min(self.min.x, other.min.x),
                Swift.min(self.min.y, other.min.y),
                Swift.min(self.min.z, other.min.z)
            ),
            max: SIMD3<Float>(
                Swift.max(self.max.x, other.max.x),
                Swift.max(self.max.y, other.max.y),
                Swift.max(self.max.z, other.max.z)
            )
        )
    }
    
    public func toMDLAxisAlignedBoundingBox() -> MDLAxisAlignedBoundingBox {
        return MDLAxisAlignedBoundingBox(
            maxBounds: vector_float3(max.x, max.y, max.z),
            minBounds: vector_float3(min.x, min.y, min.z)
        )
    }
}
// ============================================================================
// POLYGON OPERATIONS
// ============================================================================

/// Get the center point of a polygon
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
    guard !polygon.isEmpty else { return (SIMD2<Float>(0, 0), SIMD2<Float>(0, 0)) }
    
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

/// Calculate the area of a polygon
public func getPolygonArea(polygon: [SIMD2<Float>]) -> Float {
    guard polygon.count >= 3 else { return 0 }
    
    var area: Float = 0
    let n = polygon.count
    
    for i in 0..<n {
        let j = (i + 1) % n
        area += polygon[i].x * polygon[j].y
        area -= polygon[j].x * polygon[i].y
    }
    
    return abs(area) / 2.0
}

// ============================================================================
// POINT IN POLYGON TESTS
// ============================================================================

/// Check if a point is inside a polygon (ray casting algorithm)
public func isPointInPolygon(point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
    guard polygon.count >= 3 else { return false }
    
    var inside = false
    let n = polygon.count
    var j = n - 1
    
    for i in 0..<n {
        let pi = polygon[i]
        let pj = polygon[j]
        
        if ((pi.y > point.y) != (pj.y > point.y)) &&
           (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
            inside = !inside
        }
        
        j = i
    }
    
    return inside
}

/// Check if a point is inside a polygon with a safety margin
public func isPointInPolygonWithMargin(point: SIMD2<Float>, polygon: [SIMD2<Float>], margin: Float) -> Bool {
    guard polygon.count >= 3 else { return false }
    
    // First check if point is in polygon
    if !isPointInPolygon(point: point, polygon: polygon) {
        return false
    }
    
    // Check distance to each edge
    for i in 0..<polygon.count {
        let j = (i + 1) % polygon.count
        let p1 = polygon[i]
        let p2 = polygon[j]
        
        let distance = distancePointToLineSegment(point: point, lineStart: p1, lineEnd: p2)
        
        if distance < margin {
            return false  // Too close to edge
        }
    }
    
    return true
}

/// Calculate distance from point to line segment
func distancePointToLineSegment(point: SIMD2<Float>, lineStart: SIMD2<Float>, lineEnd: SIMD2<Float>) -> Float {
    let line = lineEnd - lineStart
    let lineLength = simd_length(line)
    
    guard lineLength > 0.001 else {
        return simd_length(point - lineStart)
    }
    
    let t = max(0.0, min(1.0, dot(point - lineStart, line) / (lineLength * lineLength)))
    let projection = lineStart + line * t
    
    return simd_length(point - projection)
}

// ============================================================================
// LAYOUT VALIDATION
// ============================================================================

/// Validate and fix furniture layout to ensure all items are within polygon
public func validateAndFixLayout(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    margin: Float = 0.4
) -> [PlacedFurniture] {
    
    print("\n✓ Validating furniture positions...")
    
    var validatedLayout: [PlacedFurniture] = []
    
    for item in layout {
        let pos2D = SIMD2<Float>(item.position.x, item.position.z)
        
        if isPointInPolygonWithMargin(point: pos2D, polygon: polygon, margin: margin) {
            validatedLayout.append(item)
            print("  ✅ \(item.category) is within bounds")
        } else {
            print("  ⚠️ \(item.category) is outside bounds, finding valid position...")
            
            // Try to find a valid position nearby
            if let fixedItem = findNearestValidPosition(
                for: item,
                polygon: polygon,
                margin: margin
            ) {
                validatedLayout.append(fixedItem)
                print("  ✅ Relocated \(item.category) to valid position")
            } else {
                print("  ❌ Could not find valid position for \(item.category) - removing")
            }
        }
    }
    
    print("\n✅ Validation complete: \(validatedLayout.count)/\(layout.count) items valid")
    return validatedLayout
}

/// Find the nearest valid position inside polygon for a furniture item
func findNearestValidPosition(
    for item: PlacedFurniture,
    polygon: [SIMD2<Float>],
    margin: Float
) -> PlacedFurniture? {
    
    let pos2D = SIMD2<Float>(item.position.x, item.position.z)
    let center = getPolygonCenter(polygon: polygon)
    
    // Binary search along line from current position to center
    var low: Float = 0.0
    var high: Float = 1.0
    var bestT: Float? = nil
    
    for _ in 0..<20 {
        let mid = (low + high) / 2.0
        let testPos = pos2D + (center - pos2D) * mid
        
        if isPointInPolygonWithMargin(point: testPos, polygon: polygon, margin: margin) {
            bestT = mid
            high = mid
        } else {
            low = mid
        }
    }
    
    guard let t = bestT else { return nil }
    
    let validPos2D = pos2D + (center - pos2D) * t
    let validPos3D = SIMD3<Float>(validPos2D.x, item.position.y, validPos2D.y)
    
    return PlacedFurniture(
        position: validPos3D,
        rotation: item.rotation,
        category: item.category
    )
}

// ============================================================================
// CONVEX HULL (for polygon simplification)
// ============================================================================

/// Compute convex hull of points using Graham scan algorithm
public func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
    guard points.count >= 3 else { return points }
    
    // Find point with lowest y-coordinate (and leftmost if tie)
    var lowest = points[0]
    var lowestIndex = 0
    
    for (i, point) in points.enumerated() {
        if point.y < lowest.y || (point.y == lowest.y && point.x < lowest.x) {
            lowest = point
            lowestIndex = i
        }
    }
    
    // Sort points by polar angle with respect to lowest point
    var sortedPoints = points
    sortedPoints.remove(at: lowestIndex)
    
    sortedPoints.sort { p1, p2 in
        let angle1 = atan2(p1.y - lowest.y, p1.x - lowest.x)
        let angle2 = atan2(p2.y - lowest.y, p2.x - lowest.x)
        return angle1 < angle2
    }
    
    // Build convex hull
    var hull: [SIMD2<Float>] = [lowest]
    
    for point in sortedPoints {
        while hull.count >= 2 {
            let p1 = hull[hull.count - 2]
            let p2 = hull[hull.count - 1]
            
            // Check if we make a left turn
            let cross = (p2.x - p1.x) * (point.y - p1.y) - (p2.y - p1.y) * (point.x - p1.x)
            
            if cross <= 0 {
                hull.removeLast()
            } else {
                break
            }
        }
        
        hull.append(point)
    }
    
    return hull
}

// ============================================================================
// FLOOR POLYGON EXTRACTION
// ============================================================================

/// Extract floor polygon from mesh vertices
public func extractFloorPolygon(from mesh: MDLMesh) -> [SIMD2<Float>]? {
    guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition) else {
        print("⚠️ No position attribute found")
        return nil
    }
    
    let vertexCount = mesh.vertexCount
    var vertices2D: [SIMD2<Float>] = []
    
    let dataPointer = positions.dataStart.assumingMemoryBound(to: Float.self)
    let stride = positions.stride / MemoryLayout<Float>.size
    
    for i in 0..<vertexCount {
        let index = i * stride
        let x = dataPointer[index]
        let z = dataPointer[index + 2]  // Y is up, so we use X and Z for 2D
        
        vertices2D.append(SIMD2<Float>(x, z))
    }
    
    // Remove duplicate vertices
    var uniqueVertices: [SIMD2<Float>] = []
    var seen: Set<String> = []

    for vertex in vertices2D {
        let key = "\(vertex.x)_\(vertex.y)"
        if !seen.contains(key) {
            seen.insert(key)
            uniqueVertices.append(vertex)
        }
    }
    vertices2D = uniqueVertices
    guard vertices2D.count >= 3 else {
        print("⚠️ Not enough unique vertices")
        return nil
    }
    
    // Compute convex hull to get boundary polygon
    let polygon = convexHull(vertices2D)
    
    print("✅ Extracted floor polygon with \(polygon.count) vertices")
    return polygon
}

// ============================================================================
// DISTANCE CALCULATIONS
// ============================================================================

/// Calculate distance between two 2D points
public func distance2D(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>) -> Float {
    return simd_length(p2 - p1)
}

/// Calculate distance between two 3D points
public func distance3D(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Float {
    return simd_length(p2 - p1)
}
