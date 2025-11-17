import RealityKit
import simd
import UIKit

// ============================================================================
// DEBUG VISUALIZATION HELPERS
// ============================================================================
// Add these functions to help you visualize the floor polygon and safe zones

/// Create a visual representation of the floor polygon boundary
func createFloorPolygonVisualization(polygon: [SIMD2<Float>], height: Float = 0.01, color: UIColor = .green) -> ModelEntity {
    
    // Create a path from the polygon points
    guard polygon.count >= 3 else {
        return ModelEntity()
    }
    
    var meshDescriptor = MeshDescriptor()
    
    // Create vertices at the polygon points (raised slightly for visibility)
    var vertices: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    
    // Add all polygon vertices at the specified height
    for point in polygon {
        vertices.append(SIMD3<Float>(point.x, height, point.y))
    }
    
    // Create triangle fan from the center to form the floor plane
    let center = getPolygonCenter(polygon: polygon)
    let centerVertex = SIMD3<Float>(center.x, height, center.y)
    vertices.append(centerVertex) // Add center as last vertex
    let centerIndex = UInt32(vertices.count - 1)
    
    // Create triangles from center to each edge
    for i in 0..<polygon.count {
        let next = (i + 1) % polygon.count
        
        indices.append(centerIndex)
        indices.append(UInt32(i))
        indices.append(UInt32(next))
    }
    
    meshDescriptor.positions = MeshBuffer(vertices)
    meshDescriptor.primitives = .triangles(indices)
    
    // Create the mesh resource
    let mesh = try! MeshResource.generate(from: [meshDescriptor])
    
    // Create material
    var material = SimpleMaterial()
    material.baseColor = .color(color.withAlphaComponent(0.3)) // Semi-transparent
    material.roughness = 0.5
    
    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.name = "FloorPolygonVisualization"
    
    return entity
}

/// Create edge lines around the floor polygon for clear boundary visualization
func createPolygonBoundaryLines(polygon: [SIMD2<Float>], height: Float = 0.02, color: UIColor = .red, thickness: Float = 0.05) -> Entity {
    
    let parent = Entity()
    parent.name = "PolygonBoundaryLines"
    
    for i in 0..<polygon.count {
        let next = (i + 1) % polygon.count
        
        let p1 = SIMD3<Float>(polygon[i].x, height, polygon[i].y)
        let p2 = SIMD3<Float>(polygon[next].x, height, polygon[next].y)
        
        // Create a thin box between the two points
        let direction = p2 - p1
        let distance = length(direction)
        let midpoint = (p1 + p2) / 2
        
        if distance < 0.001 { continue }
        
        // Create cylinder mesh for the edge
        let mesh = MeshResource.generateBox(size: [thickness, thickness, distance])
        
        var material = SimpleMaterial()
        material.baseColor = .color(color)
        material.roughness = 0.2
        
        let lineEntity = ModelEntity(mesh: mesh, materials: [material])
        
        // Position at midpoint
        lineEntity.position = midpoint
        
        // Rotate to align with direction
        let angle = atan2(direction.x, direction.z)
        lineEntity.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        
        parent.addChild(lineEntity)
    }
    
    return parent
}

/// Create a visual marker at a specific 2D position
func createPositionMarker(at position: SIMD2<Float>, height: Float = 0.1, color: UIColor = .blue, label: String = "") -> Entity {
    
    let parent = Entity()
    parent.name = "PositionMarker_\(label)"
    
    // Create small sphere at position
    let mesh = MeshResource.generateSphere(radius: 0.1)
    var material = SimpleMaterial()
    material.baseColor = .color(color)
    
    let marker = ModelEntity(mesh: mesh, materials: [material])
    marker.position = SIMD3<Float>(position.x, height, position.y)
    
    parent.addChild(marker)
    
    return parent
}

/// Create a grid of markers showing the safe placement zone
func createSafePlacementZoneVisualization(
    polygon: [SIMD2<Float>],
    margin: Float = 0.4,
    gridSpacing: Float = 0.5,
    height: Float = 0.05
) -> Entity {
    
    let parent = Entity()
    parent.name = "SafePlacementZone"
    
    let bounds = getPolygonBounds(polygon: polygon)
    
    // Create grid of test points
    var x = bounds.min.x + margin
    while x <= bounds.max.x - margin {
        var z = bounds.min.y + margin
        while z <= bounds.max.y - margin {
            
            let point = SIMD2<Float>(x, z)
            
            // Check if point is in safe zone
            if isPointInPolygonWithMargin(point: point, polygon: polygon, margin: margin) {
                // Create small green sphere for valid positions
                let mesh = MeshResource.generateSphere(radius: 0.05)
                var material = SimpleMaterial()
                material.baseColor = .color(UIColor.green.withAlphaComponent(0.5))
                
                let marker = ModelEntity(mesh: mesh, materials: [material])
                marker.position = SIMD3<Float>(x, height, z)
                
                parent.addChild(marker)
            }
            
            z += gridSpacing
        }
        x += gridSpacing
    }
    
    return parent
}

// ============================================================================
// USAGE INSTRUCTIONS
// ============================================================================

/*
 HOW TO USE THESE DEBUG VISUALIZATIONS:
 
 1. In your PreviewView's RealityView, after loading the room, add:
 
    if let layout = generatedLayout {
        // Add floor polygon visualization
        if let floorElement = coordinator.structuralElements.first(where: { $0.type == "floor" }),
           let polygonData = floorElement.polygon {
            let polygon = polygonData.map { SIMD2<Float>($0[0], $0[1]) }
            
            // Show floor polygon area
            let floorVis = createFloorPolygonVisualization(
                polygon: polygon,
                height: 0.01,
                color: .green
            )
            anchor.addChild(floorVis)
            
            // Show boundary lines
            let boundaryLines = createPolygonBoundaryLines(
                polygon: polygon,
                height: 0.02,
                color: .red,
                thickness: 0.05
            )
            anchor.addChild(boundaryLines)
            
            // Show safe placement zone
            let safeZone = createSafePlacementZoneVisualization(
                polygon: polygon,
                margin: 0.4,
                gridSpacing: 0.5,
                height: 0.05
            )
            anchor.addChild(safeZone)
            
            // Mark furniture positions
            for (index, furniture) in layout.enumerated() {
                let marker = createPositionMarker(
                    at: SIMD2<Float>(furniture.position.x, furniture.position.z),
                    height: 0.15,
                    color: .blue,
                    label: "\(index)_\(furniture.category)"
                )
                anchor.addChild(marker)
            }
        }
    }
 
 2. This will show you:
    - Green semi-transparent floor polygon (where furniture CAN be placed)
    - Red lines around the boundary (walls)
    - Small green dots showing safe placement zone (with margin)
    - Blue spheres at each furniture position
 
 3. If furniture appears outside the red lines, you'll immediately see the problem!
 
 4. To toggle these visualizations on/off, you can add a button:
 
    @State private var showDebugVisuals = false
    
    Then wrap the visualization code in:
    if showDebugVisuals {
        // ... visualization code ...
    }
*/

// ============================================================================
// QUICK FIX CHECKLIST
// ============================================================================

/*
 IF FURNITURE IS STILL APPEARING OUTSIDE THE ROOM:
 
 ✓ 1. Check the console logs:
      - Look for "Floor polygon area: X m²" - should be > 1.0
      - Look for "FOUND X INVALID POSITIONS" messages
      - Look for "STILL INVALID" warnings in final verification
 
 ✓ 2. Enable debug visualizations (code above) to SEE the polygon
 
 ✓ 3. Check your 3d.usdz file:
      - Open it in Xcode or Reality Composer
      - Verify there's a mesh named "floor" or containing "floor"
      - Check that the floor is a proper horizontal surface
 
 ✓ 4. Verify the AI is receiving correct bounds:
      - Check the console for "ABSOLUTE POSITION CONSTRAINTS"
      - Ensure the min/max values make sense for your room
 
 ✓ 5. If the polygon extraction is failing:
      - The extractFloorPolygon() function might need adjustment
      - Try using a convex hull instead (already implemented as fallback)
      - Check for duplicate vertices in the mesh
 
 ✓ 6. If AI ignores the constraints:
      - The enhanced prompt now explicitly states constraints multiple times
      - Increased the safe margin from 0.3m to 0.4m
      - Added verification step in the AI prompt
 
 ✓ 7. If validation is not working:
      - The validateAndFixLayout() function uses binary search
      - If it returns nil for a position, furniture is removed
      - Check that findNearestValidPosition() is working correctly
*/
