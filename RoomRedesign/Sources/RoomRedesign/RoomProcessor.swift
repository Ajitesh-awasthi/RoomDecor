import Foundation
import ModelIO
import RealityKit
import simd
import UniformTypeIdentifiers
import MetalKit
import UIKit // <-- We just import UIKit directly

// This file is now iOS-compatible (UIColor)
public typealias PlatformColor = UIColor // <-- And we just typealias UIColor

// --- CATEGORY LISTS (LOCAL) ---
let localStructuralCategories: Set<String> = [
    "wall", "floor", "ceiling", "door", "window"
]
let localFurnitureCategories: Set<String> = [
    "furniture", "chair", "table", "television", "sofa", "couch",
    "plant", "lamp", "rug", "object", "shelf", "cabinet"
]

// --- NEW: A struct to hold data about walls/floors ---
struct StructuralElement: Codable {
    let id: String           // The entity name
    let type: String         // "wall", "floor", "door", "window", etc.
    
    let minBounds: [Float]     // [x, y, z]
    let maxBounds: [Float]     // [x, y, z]

    let normal: [Float]?       // For walls → interior-facing normal (x, y, z)
    let thickness: Float?      // For walls
    let isOpening: Bool?       // For doors/windows

    let polygon: [[Float]]?    // For floor: [[x, z], ...]  (2D polygon)
    
    //---------------------------------------------------------
    // MARK: - Initializer for walls/floors/doors/windows
    //---------------------------------------------------------
    init(
        id: String,
        type: String,
        bounds: BoundingBox, // <-- This is the param we use
        normal: SIMD3<Float>? = nil,
        thickness: Float? = nil,
        isOpening: Bool? = nil,
        polygon: [SIMD2<Float>]? = nil
    ) {
        self.id = id
        self.type = type
        
        self.minBounds = [bounds.min.x, bounds.min.y, bounds.min.z]
        self.maxBounds = [bounds.max.x, bounds.max.y, bounds.max.z]

        if let n = normal {
            self.normal = [n.x, n.y, n.z]
        } else {
            self.normal = nil
        }
        
        self.thickness = thickness
        self.isOpening = isOpening
        
        if let poly = polygon {
            self.polygon = poly.map { [ $0.x, $0.y ] } // .y is z-coord in 2D
        } else {
            self.polygon = nil
        }
    }
}



// -----------------------------------------------------------------------------
// MARK: - MESH REPORT (for debugging USDZ contents)
// -----------------------------------------------------------------------------
public func dumpAssetMeshReport(inputURL: URL) {
    let asset = MDLAsset(url: inputURL)
    guard asset.count > 0 else {
        print("dumpAssetMeshReport: asset empty")
        return
    }

    var lines: [String] = []

    func recurse(_ obj: MDLObject, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        var info = "\(indent)- \(obj.name) (\(type(of: obj)))"

        if let mesh = obj as? MDLMesh {
            let bb = mesh.boundingBox(atTime: 0)
            let sx = bb.maxBounds.x - bb.minBounds.x
            let sy = bb.maxBounds.y - bb.minBounds.y
            let sz = bb.maxBounds.z - bb.minBounds.z
            info += String(format: "  size=%.3fm x %.3fm x %.3fm", Double(sx), Double(sy), Double(sz))
        }

        print(info)
        lines.append(info)

        for c in obj.children.objects {
            if let mdl = c as? MDLObject {
                recurse(mdl, depth: depth + 1)
            }
        }
    }

    recurse(asset.object(at: 0), depth: 0)

    // Note: iOS sandboxing might prevent writing to Documents.
    // This is primarily for debugging.
    do {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first!
        let outFile = docs.appendingPathComponent("usd_mesh_report.txt")
        try lines.joined(separator: "\n").write(to: outFile,
                                               atomically: true,
                                               encoding: .utf8)
        print("Mesh report written to: \(outFile.path)")
    } catch {
        print("Failed to write mesh report:", error)
    }
}

// -----------------------------------------------------------------------------
// MARK: - MATERIAL HELPER
// -----------------------------------------------------------------------------
public func makeMaterial(_ color: PlatformColor,
                   alpha: CGFloat = 1.0,
                   isMetallic: Bool = false) -> SimpleMaterial {
    var mat = SimpleMaterial()
    mat.baseColor = .color(color.withAlphaComponent(alpha))
    mat.metallic = isMetallic ? 1.0 : 0.0
    mat.roughness = 0.3
    return mat
}

// -----------------------------------------------------------------------------
// MARK: - "HIDE-IN-PLACE" ROOM PROCESSOR (FOR REAL-TIME USE)
// -----------------------------------------------------------------------------

@discardableResult
func processLoadedRoom(entity: Entity) -> (overallBounds: BoundingBox, elements: [StructuralElement]) {
    
    var combinedBounds: BoundingBox?
    var elements: [StructuralElement] = []
    
    let children = entity.children.map { $0 }
    
    
    for child in children {
        let lname = child.name.lowercased()
        
        //-------------------------------------------------------
        // 1. IGNORE PRE-EXISTING FURNITURE
        //-------------------------------------------------------
        let isFurniture = localFurnitureCategories.contains { lname.contains($0) }
        if isFurniture {
            print("❌ HIDING furniture entity: \(child.name)")
            child.isEnabled = false // Simply hide it
            continue // Don't process children of hidden objects
        }
        
        //-------------------------------------------------------
        // 2. DETECT STRUCTURAL ELEMENTS
        //-------------------------------------------------------
        let isStructural = localStructuralCategories.contains { lname.contains($0) }
        
        var currentElement: StructuralElement? = nil
        var currentBounds: BoundingBox? = nil
        
        if isStructural, let model = child as? ModelEntity {
            
            //---------------------------------------------------
            // Extract world bounds (in root coordinate space)
            //---------------------------------------------------
            let worldBounds = model.visualBounds(relativeTo: nil)
            currentBounds = worldBounds
            
            let ext = worldBounds.extents
            let ctr = worldBounds.center
            
            //---------------------------------------------------
            // WALL DETECTION & NORMAL COMPUTATION
            //---------------------------------------------------
            if lname.contains("wall") {
                
                // Walls are tall and thin in exactly one dimension.
                // Determine orientation by comparing X vs Z thickness.
                let isXThin = ext.x < ext.z   // Thin along X → wall runs along Z and normal is ±X
                let wallThickness = isXThin ? ext.x : ext.z
                
                //---------------------------------------------------
                // Determine interior-facing normal direction
                //---------------------------------------------------
                
                var normal = SIMD3<Float>(0, 0, 0)
                
                if isXThin {
                    // Wall plane runs along Z → interior faces ±X
                    normal = ctr.x > 0 ? SIMD3(-1, 0, 0) : SIMD3(1, 0, 0)
                } else {
                    // Wall plane runs along X → interior faces ±Z
                    normal = ctr.z > 0 ? SIMD3(0, 0, -1) : SIMD3(0, 0, 1)
                }
                
                //---------------------------------------------------
                // Build structural element
                //---------------------------------------------------
                currentElement = StructuralElement(
                    id: child.name,
                    type: "wall",
                    bounds: worldBounds, // <-- Use the BoundingBox
                    normal: normal,
                    thickness: wallThickness,
                    isOpening: false,
                    polygon: nil
                )
            }
            
            //---------------------------------------------------
            // FLOOR DETECTION & FLOOR POLYGON EXTRACTION
            //---------------------------------------------------
            else if lname.contains("floor") {
                
                // Extract 2D polygon from floor mesh (XZ plane)
                let polygon = extractFloorPolygonConcave(from: model)
                
                currentElement = StructuralElement(
                    id: child.name,
                    type: "floor",
                    bounds: worldBounds, // <-- Use the BoundingBox
                    normal: SIMD3<Float>(0, 1, 0), // floor normal always up
                    thickness: nil,
                    isOpening: false,
                    polygon: polygon
                )
                
                // Add collision so AR raycasts work
                let shape = ShapeResource.generateBox(size: worldBounds.extents)
                    .offsetBy(translation: worldBounds.center)
                let collision = CollisionComponent(shapes: [shape], mode: .trigger, filter: .default)
                model.components.set(collision)
            }
            
            //---------------------------------------------------
            // DOOR DETECTION (OPENING)
            //---------------------------------------------------
            else if lname.contains("door") {
                currentElement = StructuralElement(
                    id: child.name,
                    type: "door",
                    bounds: worldBounds, // <-- Use the BoundingBox
                    normal: nil,
                    thickness: nil,
                    isOpening: true,
                    polygon: nil
                )
            }
            
            //---------------------------------------------------
            // WINDOW DETECTION (OPENING)
            //---------------------------------------------------
            else if lname.contains("window") {
                currentElement = StructuralElement(
                    id: child.name,
                    type: "window",
                    bounds: worldBounds, // <-- Use the BoundingBox
                    normal: nil,
                    thickness: nil,
                    isOpening: true,
                    polygon: nil
                )
            }
        }
        
        //-------------------------------------------------------
        // 3. PROCESS CHILDREN RECURSIVELY
        //-------------------------------------------------------
        let childAnalysis = processLoadedRoom(entity: child)
        let childBounds = childAnalysis.overallBounds
        let childElements = childAnalysis.elements
        
        elements.append(contentsOf: childElements)
        if let element = currentElement { elements.append(element) }
        
        
        
        
        //-------------------------------------------------------
        // 4. ACCUMULATE BOUNDS
        //-------------------------------------------------------
        var branchBounds = currentBounds
        
        if childBounds.min != .zero || childBounds.max != .zero {
            if let b = branchBounds {
                branchBounds = b.union(childBounds)
            } else {
                branchBounds = childBounds
            }
        }
        
        if let existing = combinedBounds, let new = branchBounds {
            combinedBounds = existing.union(new)
        } else if combinedBounds == nil {
            combinedBounds = branchBounds
        }
    }
    
    return (combinedBounds ?? BoundingBox(min: .zero, max: .zero), elements)
}

// -----------------------------------------------------------------------------
// MARK: - FLOOR POLYGON EXTRACTION (FIXED VERSION)
// -----------------------------------------------------------------------------

// MARK: - SUPPORT TYPES FOR CONCAVE POLYGON EXTRACTION

/// Represents an undirected mesh edge between vertex indices.
/// Used for detecting boundary edges (edges belonging to exactly one triangle).
struct Edge: Hashable {
    let a: Int
    let b: Int

    init(_ i: Int, _ j: Int) {
        // Always store smallest index in `a` so edge direction doesn't matter
        if i < j {
            self.a = i
            self.b = j
        } else {
            self.a = j
            self.b = i
        }
    }
}

/// Increments the count for a given mesh edge.
/// Boundary edges will appear exactly once.
func addEdge(_ i: Int, _ j: Int, _ map: inout [Edge: Int]) {
    let e = Edge(i, j)
    map[e, default: 0] += 1
}

// IMPROVED POLYGON EXTRACTION FOR RoomProcessor.swift
// Replace the extractFloorPolygonConcave function with this version

func extractFloorPolygonConcave(from model: ModelEntity) -> [SIMD2<Float>] {
    guard let mesh = model.model?.mesh else {
        print("⚠️ No mesh found in model")
        return []
    }

    var vertices: [SIMD2<Float>] = []
    var edgesCount: [Edge: Int] = [:]

    // STEP 1 — Iterate each MeshResource.Model
    for mdl in mesh.contents.models {
        for part in mdl.parts {

            // ---- EXTRACT positions from MeshBuffer ----
            let positionsBuffer = part.positions
            
            // Check if buffer has content by accessing it
            var positionsArray: [SIMD3<Float>] = []
            positionsBuffer.forEach { position in
                positionsArray.append(position)
            }
            
            // If no positions, skip this part
            if positionsArray.isEmpty {
                continue
            }

            // Transform local → world
            let worldVerts: [SIMD3<Float>] = positionsArray.map { local in
                let wp = model.transform.matrix * SIMD4<Float>(local, 1)
                return SIMD3<Float>(wp.x, wp.y, wp.z)
            }

            // Store all vertices into our local list
            // IMPORTANT: We track the base index so global vertex IDs remain unique.
            let baseIndex = vertices.count
            for v in worldVerts {
                vertices.append(SIMD2(v.x, v.z))
            }

            // ---- EXTRACT triangle indices from MeshBuffer ----
            guard let triangleIndicesBuffer = part.triangleIndices else {
                continue
            }
            
            // Convert MeshBuffer to array
            var triangleIndicesArray: [UInt32] = []
            triangleIndicesBuffer.forEach { index in
                triangleIndicesArray.append(index)
            }
            
            // Process triangles (indices come in groups of 3)
            for i in stride(from: 0, to: triangleIndicesArray.count, by: 3) {
                guard i + 2 < triangleIndicesArray.count else { break }
                
                let i0 = baseIndex + Int(triangleIndicesArray[i])
                let i1 = baseIndex + Int(triangleIndicesArray[i + 1])
                let i2 = baseIndex + Int(triangleIndicesArray[i + 2])

                addEdge(i0, i1, &edgesCount)
                addEdge(i1, i2, &edgesCount)
                addEdge(i2, i0, &edgesCount)
            }
        }
    }

    if vertices.isEmpty {
        print("⚠️ No vertices extracted from floor mesh")
        return []
    }

    print("✅ Extracted \(vertices.count) vertices from floor mesh")

    // STEP 2 — Extract boundary edges (count == 1)
    let boundaryEdges = edgesCount.filter { $0.value == 1 }.map { $0.key }
    if boundaryEdges.isEmpty {
        print("⚠️ No boundary edges found")
        return []
    }

    print("✅ Found \(boundaryEdges.count) boundary edges")

    // STEP 3 — Build adjacency map
    var adjacency: [Int: [Int]] = [:]
    for e in boundaryEdges {
        adjacency[e.a, default: []].append(e.b)
        adjacency[e.b, default: []].append(e.a)
    }

    // STEP 4 — Find a start (any)
    guard let start = adjacency.keys.first else {
        print("⚠️ No start vertex found")
        return []
    }

    // STEP 5 — Follow edges to form polygon
    var rawPolygon: [SIMD2<Float>] = []
    var visited = Set<Int>()

    var current = start
    var previous = -1

    while true {
        rawPolygon.append(vertices[current])
        visited.insert(current)

        let neighbors = adjacency[current] ?? []
        let next = neighbors.first { $0 != previous } ?? neighbors.first

        if next == nil { break }
        previous = current
        current = next!

        if current == start { break }
    }

    print("✅ Extracted raw polygon with \(rawPolygon.count) vertices")
    
    // STEP 6 — DEDUPLICATE VERTICES (NEW!)
    var deduplicatedPolygon: [SIMD2<Float>] = []
    let epsilon: Float = 0.01 // 1cm tolerance for duplicate detection
    
    for vertex in rawPolygon {
        // Check if this vertex is too close to any existing vertex
        var isDuplicate = false
        for existing in deduplicatedPolygon {
            if length(vertex - existing) < epsilon {
                isDuplicate = true
                break
            }
        }
        
        if !isDuplicate {
            deduplicatedPolygon.append(vertex)
        } else {
            print("🔧 Skipped duplicate vertex: (\(String(format: "%.2f", vertex.x)), \(String(format: "%.2f", vertex.y)))")
        }
    }
    
    print("✅ After deduplication: \(deduplicatedPolygon.count) unique vertices")
    
    // STEP 7 — If still not enough vertices, use convex hull of all floor vertices
    if deduplicatedPolygon.count < 3 {
        print("⚠️ Not enough unique boundary vertices. Computing convex hull of all floor vertices...")
        
        // Deduplicate all vertices first
        var uniqueVertices: [SIMD2<Float>] = []
        for vertex in vertices {
            var isDuplicate = false
            for existing in uniqueVertices {
                if length(vertex - existing) < epsilon {
                    isDuplicate = true
                    break
                }
            }
            if !isDuplicate {
                uniqueVertices.append(vertex)
            }
        }
        
        print("🔍 Found \(uniqueVertices.count) unique vertices in floor mesh")
        
        // Compute convex hull
        var hullInput = uniqueVertices
        let hull = convexHull(points: &hullInput)
        
        print("✅ Computed convex hull with \(hull.count) vertices")
        
        // Print hull for debugging
        print("📐 Convex hull vertices:")
        for (i, point) in hull.enumerated() {
            print("  [\(i)]: (\(String(format: "%.2f", point.x)), \(String(format: "%.2f", point.y)))")
        }
        
        return hull
    }
    
    // Print final polygon for debugging
    print("📐 Floor polygon vertices:")
    for (i, point) in deduplicatedPolygon.enumerated() {
        print("  [\(i)]: (\(String(format: "%.2f", point.x)), \(String(format: "%.2f", point.y)))")
    }

    return deduplicatedPolygon
}


// -----------------------------------------------------------------------------
// MARK: - CONVEX HULL ALGORITHM (Monotone Chain)
// -----------------------------------------------------------------------------
private func crossProduct(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ o: SIMD2<Float>) -> Float {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
}

func convexHull(points: inout [SIMD2<Float>]) -> [SIMD2<Float>] {
    guard points.count > 2 else { return points }
    
    // Sort points lexicographically
    points.sort { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
    
    var lower: [SIMD2<Float>] = []
    for p in points {
        while lower.count >= 2 && crossProduct(lower[lower.count - 2], lower.last!, p) <= 0 {
            lower.removeLast()
        }
        lower.append(p)
    }
    
    var upper: [SIMD2<Float>] = []
    for p in points.reversed() {
        while upper.count >= 2 && crossProduct(upper[upper.count - 2], upper.last!, p) <= 0 {
            upper.removeLast()
        }
        upper.append(p)
    }
    
    // Remove last point of each hull (it's repeated)
    lower.removeLast()
    upper.removeLast()
    
    // Join hulls
    return lower + upper
}
