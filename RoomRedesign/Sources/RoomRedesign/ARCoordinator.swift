import SwiftUI
import RealityKit
import ARKit
import UIKit
import ModelIO

// ============================================================================
// DOOR DETECTION SYSTEM
// ============================================================================
struct DoorInfo {
    let position: SIMD2<Float>
    let width: Float
    let direction: SIMD2<Float>
}
// Helper to check if item is a wall decoration
private func isWallItem(_ category: String) -> Bool {
    return category == "Painting" ||
           category == "Wall_Clock" ||
           category == "Wall Clock"
}


func extractDoorLocations(from elements: [StructuralElement]) -> [DoorInfo] {
    var doors: [DoorInfo] = []
    
    for element in elements {
        if element.type == "door" || (element.id.lowercased().contains("door")) {
            let centerX = (element.minBounds[0] + element.maxBounds[0]) / 2
            let centerZ = (element.minBounds[2] + element.maxBounds[2]) / 2
            let position = SIMD2<Float>(centerX, centerZ)
            
            let widthX = element.maxBounds[0] - element.minBounds[0]
            let widthZ = element.maxBounds[2] - element.minBounds[2]
            let width = max(widthX, widthZ)
            
            let direction: SIMD2<Float>
            if widthX > widthZ {
                direction = SIMD2<Float>(0, 1)
            } else {
                direction = SIMD2<Float>(1, 0)
            }
            
            doors.append(DoorInfo(position: position, width: width, direction: direction))
            print("🚪 Detected door at (\(centerX), \(centerZ)) with width \(width)m")
        }
    }
    
    return doors
}

func isNearDoor(position: SIMD2<Float>, doors: [DoorInfo], clearanceRadius: Float = 2.0) -> Bool {
    for door in doors {
        let distance = length(position - door.position)
        if distance < clearanceRadius {
            return true
        }
    }
    return false
}

// ============================================================================
// THEME SYSTEM
// ============================================================================
struct RoomTheme {
    let wallColors: [UIColor]
    let floorColor: UIColor?
    let name: String
}

let predefinedThemes: [String: RoomTheme] = [
    "modern": RoomTheme(
        wallColors: [
            UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
            UIColor(red: 0.85, green: 0.85, blue: 0.90, alpha: 1.0)
        ],
        floorColor: UIColor(red: 0.8, green: 0.75, blue: 0.68, alpha: 1.0),
        name: "Modern"
    ),
    "warm": RoomTheme(
        wallColors: [
            UIColor(red: 0.98, green: 0.94, blue: 0.85, alpha: 1.0),
            UIColor(red: 0.95, green: 0.88, blue: 0.78, alpha: 1.0)
        ],
        floorColor: UIColor(red: 0.65, green: 0.45, blue: 0.30, alpha: 1.0),
        name: "Warm"
    ),
    "cool": RoomTheme(
        wallColors: [
            UIColor(red: 0.88, green: 0.92, blue: 0.95, alpha: 1.0),
            UIColor(red: 0.85, green: 0.90, blue: 0.92, alpha: 1.0)
        ],
        floorColor: UIColor(red: 0.7, green: 0.7, blue: 0.75, alpha: 1.0),
        name: "Cool"
    ),
    "natural": RoomTheme(
        wallColors: [
            UIColor(red: 0.93, green: 0.95, blue: 0.88, alpha: 1.0),
            UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1.0)
        ],
        floorColor: UIColor(red: 0.55, green: 0.40, blue: 0.25, alpha: 1.0),
        name: "Natural"
    ),
    "elegant": RoomTheme(
        wallColors: [
            UIColor(red: 0.92, green: 0.90, blue: 0.88, alpha: 1.0),
            UIColor(red: 0.88, green: 0.85, blue: 0.82, alpha: 1.0)
        ],
        floorColor: UIColor(red: 0.3, green: 0.3, blue: 0.32, alpha: 1.0),
        name: "Elegant"
    )
]

func detectThemeFromPrompt(_ prompt: String) -> RoomTheme {
    let lowercased = prompt.lowercased()
    
    // Modern/Minimalist/Contemporary
    if lowercased.contains("modern") ||
       lowercased.contains("minimalist") ||
       lowercased.contains("contemporary") ||
       lowercased.contains("sleek") ||
       lowercased.contains("simple") {
        return predefinedThemes["modern"]!
    }
    
    // Warm/Cozy/Traditional
    if lowercased.contains("warm") ||
       lowercased.contains("cozy") ||
       lowercased.contains("traditional") ||
       lowercased.contains("comfortable") ||
       lowercased.contains("inviting") {
        return predefinedThemes["warm"]!
    }
    
    // Cool/Calm/Blue
    if lowercased.contains("cool") ||
       lowercased.contains("calm") ||
       lowercased.contains("blue") ||
       lowercased.contains("serene") ||
       lowercased.contains("peaceful") {
        return predefinedThemes["cool"]!
    }
    
    // Natural/Green/Organic
    if lowercased.contains("natural") ||
       lowercased.contains("green") ||
       lowercased.contains("organic") ||
       lowercased.contains("earthy") ||
       lowercased.contains("botanical") {
        return predefinedThemes["natural"]!
    }
    
    // Elegant/Luxury/Sophisticated/Aesthetic
    if lowercased.contains("elegant") ||
       lowercased.contains("luxury") ||
       lowercased.contains("sophisticated") ||
       lowercased.contains("aesthetic") ||
       lowercased.contains("beautiful") ||
       lowercased.contains("classy") ||
       lowercased.contains("refined") {
        return predefinedThemes["elegant"]!
    }
    
    return predefinedThemes["modern"]!
}
func applyThemeToRoom(roomEntity: Entity, theme: RoomTheme) {
    print("🎨 Applying \(theme.name) theme to room (floor only)...")
    
    func applyThemeRecursive(entity: Entity) {
        let name = entity.name.lowercased()
        
        if name.contains("floor"), let modelEntity = entity as? ModelEntity, let floorColor = theme.floorColor {
            var material = SimpleMaterial()
            material.baseColor = .color(floorColor)
            material.roughness = 0.8
            material.metallic = 0.0
            
            modelEntity.model?.materials = [material]
            print("  🖌️ Floor → \(theme.name) floor color")
        }
        
        for child in entity.children {
            applyThemeRecursive(entity: child)
        }
    }
    
    applyThemeRecursive(entity: roomEntity)
}

// ============================================================================
// AR COORDINATOR
// ============================================================================

class ARCoordinator: NSObject, ObservableObject {
    weak var arView: ARView?
    var furnitureAnchor = Entity()
    var roomBounds: MDLAxisAlignedBoundingBox?
    var structuralElements: [StructuralElement] = []
    var doorLocations: [DoorInfo] = []
    
    var showBoundaryWarningBinding: Binding<Bool>?
    var boundaryWarningMessageBinding: Binding<String>?
    var showDeleteConfirmationBinding: Binding<Bool>?
    var furnitureToDeleteBinding: Binding<Entity?>?
    
    @Published var sceneLoadError: String? = nil
    @Published var selectedFurniture: String? = nil
    @Published var furnitureCart: [String: Int] = [:]
    @Published var totalPrice: Float = 0.0
    
    // ✅ FIX 2: ADD THIS PROPERTY TO PREVENT MULTIPLE ADDS
    private var isPlacingFurniture = false

    func loadRoomBounds(from url: URL) {
        guard roomBounds == nil else { return } // No need to reload if already done

        // --- THIS IS THE FIX ---
        guard let roomEntity = try? Entity.load(contentsOf: url) else {
            self.sceneLoadError = "Failed to load room from URL."
            return
        }
        // -----------------------

        let analysis = processLoadedRoom(entity: roomEntity)
        self.roomBounds = analysis.overallBounds.toMDLAxisAlignedBoundingBox()
        self.structuralElements = analysis.elements
        self.doorLocations = extractDoorLocations(from: analysis.elements)
        print("✅ Room bounds and \(analysis.elements.count) structural elements loaded.")
    }

    func findDraggableParent(from entity: Entity) -> Entity? {
        if entity.name.starts(with: "FURN_") {
            return entity
        }
        guard let parent = entity.parent else { return nil }
        return findDraggableParent(from: parent)
    }
    
    func placeFurnitureList(_ list: [PlacedFurniture], in anchor: Entity, isPreview: Bool = false) { // <-- ADD THIS
        anchor.children.removeAll()
            for item in list {
                // Pass 'isPreview' to the next function
                placeFurniture(name: item.category, position: item.position, rotation: item.rotation, in: anchor, isPreview: isPreview)
            }
    }

    func placeFurniture(name: String, position: SIMD3<Float>, rotation: Float,
                           in anchor: Entity, isPreview: Bool = false) {
        let position2D = SIMD2<Float>(position.x, position.z)
        
        if let polygon = getFloorPolygon() {
            if !isPointInPolygonWithMargin(point: position2D, polygon: polygon, margin: 0.5) {
                showBoundaryWarning(message: "⚠️ Cannot place outside room boundaries!")
                return
            }
            
            if isNearDoor(position: position2D, doors: doorLocations, clearanceRadius: 1.2) {
                showBoundaryWarning(message: "⚠️ Cannot place near doorway!")
                return
            }
        }
        
        guard let modelName = furnitureAssets[name] else {
            print("Error: '\(name)' not in asset catalog.")
            return
        }
        
        do {
            let entity = try Entity.load(named: modelName, in: Bundle.module)
            let targetSize = getTargetSize(for: name, roomBounds: roomBounds)
            let normalized = normalizeFurniture(entity, targetSize: targetSize)
            
            entity.scale = normalized.scale
            entity.position = normalized.position
            
            let placedEntity = ModelEntity()
            placedEntity.addChild(entity)
            placedEntity.name = "FURN_\(name)_\(UUID().uuidString.prefix(4))"
            
            // ✅ DETERMINE Y POSITION AND ROTATION BASED ON MODE AND ITEM TYPE
            let yPosition: Float
            let finalRotation: simd_quatf
            
            if isPreview {
                // ============================================================
                // PREVIEW MODE: Use position from layout data (already correct)
                // ============================================================
                yPosition = position.y
                finalRotation = simd_quatf(angle: rotation * .pi / 180.0, axis: [0,1,0])
                print("📺 Preview: \(name) at Y=\(position.y)")
                
            } else {
                // ============================================================
                // AR MODE: Calculate position based on room scan + metadata
                // ============================================================
                let floorHeight = getFloorHeight()
                
                if isWallItem(name) {
                    print("🎨 Detected wall item: \(name)")
                       
                       if let metadata = furnitureMetadata[name] {
                           yPosition = floorHeight + metadata.heightOffset
                           print("🖼️ AR Wall item: \(name) at Y=\(yPosition) (floor: \(floorHeight) + offset: \(metadata.heightOffset))")
                           
                           let yRotation = simd_quatf(angle: rotation * .pi / 180.0, axis: [0,1,0])
                           
                           if name == "Wall_Clock" || name == "Wall Clock" {
                               // Clock needs to stand upright
                               let xRotation = simd_quatf(angle: .pi / 2, axis: [1,0,0])
                               finalRotation = yRotation * xRotation
                               print("  🕐 Clock: Applied X-axis rotation")
                           } else if name == "Painting" {
                               finalRotation = yRotation
                               print("  🖼️ Painting: Standard rotation")
                           } else {
                               finalRotation = yRotation
                           }
                       } else {
                           print("⚠️ No metadata for wall item: \(name)")
                           yPosition = floorHeight + 1.5
                           finalRotation = simd_quatf(angle: rotation * .pi / 180.0, axis: [0,1,0])
                       }
                   } else {
                       // Floor items
                       yPosition = floorHeight + 0.01
                       finalRotation = simd_quatf(angle: rotation * .pi / 180.0, axis: [0,1,0])
                       print("🪑 AR Floor item: \(name) at Y=\(yPosition)")
                   }
            }
            
            // ✅ APPLY FINAL POSITION AND ROTATION
            placedEntity.position = SIMD3<Float>(
                position.x,
                yPosition,
                position.z
            )
            
            placedEntity.transform.rotation = finalRotation
            placedEntity.generateCollisionShapes(recursive: true)
            
            anchor.addChild(placedEntity)
            print("✅ Placed: \(placedEntity.name) at Y=\(yPosition)")
            
        } catch {
            print("Failed to load model \(modelName): \(error)")
            DispatchQueue.main.async {
                self.sceneLoadError = "Failed to load \(modelName)"
            }
        }
    }

    // ============================================================
    // HELPER FUNCTION: Add this if you don't have it already
    // ============================================================
    private func isWallItem(_ category: String) -> Bool {
        return category == "Painting" ||
               category == "Wall_Clock" ||
               category == "Wall Clock"
    }

    func getCurrentLayout() -> [PlacedFurniture] {
        var currentLayout: [PlacedFurniture] = []
        
        for entity in furnitureAnchor.children {
            guard entity.name.starts(with: "FURN_"), let modelEntity = entity as? ModelEntity else {
                continue
            }
            
            let fullName = entity.name
            guard let firstUnderscore = fullName.firstIndex(of: "_"),
                  let lastUnderscore = fullName.lastIndex(of: "_"),
                  firstUnderscore != lastUnderscore
            else {
                print("Warning: Could not parse category from name: \(fullName)")
                continue
            }
            
            let categoryStartIndex = fullName.index(after: firstUnderscore)
            let category = String(fullName[categoryStartIndex..<lastUnderscore])
            let position = modelEntity.position
            let rotationAngle = modelEntity.transform.rotation.angle * (180.0 / .pi)
            
            currentLayout.append(
                PlacedFurniture(
                    position: position,
                    rotation: rotationAngle,
                    category: category
                )
            )
        }
        
        print("✅ Fetched current layout with \(currentLayout.count) items.")
        return currentLayout
    }

    private func parseCategory(from name: String) -> String? {
        guard name.starts(with: "FURN_"),
              let firstUnderscore = name.firstIndex(of: "_"),
              let lastUnderscore = name.lastIndex(of: "_"),
              firstUnderscore != lastUnderscore
        else {
            print("Warning: Could not parse category from name: \(name)")
            return nil
        }
        
        let categoryStartIndex = name.index(after: firstUnderscore)
        return String(name[categoryStartIndex..<lastUnderscore])
    }
        
    func updateTotalPrice() {
        var total: Float = 0.0
        for (category, count) in furnitureCart {
            let pricePerItem = furnitureMetadata[category]?.price ?? 0.0
            total += pricePerItem * Float(count)
        }
        
        DispatchQueue.main.async {
            self.totalPrice = total
            print("💰 Total price updated: \(total)")
        }
    }
    
    func addItemToCart(category: String) {
        DispatchQueue.main.async {
            self.furnitureCart[category, default: 0] += 1
            print("🛒 Cart Add: \(category). New count: \(self.furnitureCart[category] ?? 0)")
            self.updateTotalPrice()
        }
    }
    
    func removeItemFromCart(category: String) {
        DispatchQueue.main.async {
            guard var currentCount = self.furnitureCart[category] else {
                print("🛒 Cart Remove Error: Tried to remove \(category) but it's not in the cart.")
                return
            }
            
            currentCount -= 1
            if currentCount <= 0 {
                self.furnitureCart.removeValue(forKey: category)
                print("🛒 Cart Remove: \(category). Item removed from cart.")
            } else {
                self.furnitureCart[category] = currentCount
                print("🛒 Cart Remove: \(category). New count: \(currentCount)")
            }
            self.updateTotalPrice()
        }
    }
    
    func deleteFurniture(_ furniture: Entity) {
        print("🗑️ Deleting \(furniture.name)")
        
        if let category = self.parseCategory(from: furniture.name) {
            self.removeItemFromCart(category: category)
        }
        
        furniture.removeFromParent()
    }
    
    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
        guard let arView = arView else { return }
        guard sender.state == .began else { return }
        
        let location = sender.location(in: arView)
        guard let entity = arView.entity(at: location) else { return }
        
        guard let furniture = findDraggableParent(from: entity) else { return }
        
        print("📍 Long press detected on \(furniture.name)")
        
        DispatchQueue.main.async {
            self.furnitureToDeleteBinding?.wrappedValue = furniture
            self.showDeleteConfirmationBinding?.wrappedValue = true
        }
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        
        guard !isPlacingFurniture else {
                  print("⏳ Already placing furniture, ignoring tap")
                  return
              }
        
        let tapLocation = sender.location(in: arView)
        let entityHits = arView.entities(at: tapLocation)
        
        if let tappedEntity = entityHits.first, let draggableEntity = findDraggableParent(from: tappedEntity) {
                    print("👆 Tap: Selected \(draggableEntity.name) for manipulation")
            
            if let modelEntity = draggableEntity as? ModelEntity {
                arView.installGestures([.translation, .rotation], for: modelEntity)
                
                let subscription = modelEntity.scene?.subscribe(to: SceneEvents.Update.self) { [weak self, weak modelEntity] _ in
                    guard let self = self, let entity = modelEntity else { return }
                    
                    let pos2D = SIMD2<Float>(entity.position.x, entity.position.z)
                    
                    if let polygon = self.getFloorPolygon() {
                        if !isPointInPolygonWithMargin(point: pos2D, polygon: polygon, margin: 0.5) {
                            print("⚠️ Entity moved outside bounds, reverting position")
                            self.showBoundaryWarning(message: "⚠️ Cannot move outside room boundaries!")
                            
                            if let validPos = self.findNearestValidPosition(point: pos2D, polygon: polygon) {
                                entity.position.x = validPos.x
                                entity.position.z = validPos.y
                            }
                        }
                        
                        if isNearDoor(position: pos2D, doors: self.doorLocations, clearanceRadius: 2.0) {
                            print("⚠️ Entity too close to door")
                            self.showBoundaryWarning(message: "⚠️ Cannot place near doorway!")
                            
                            if let validPos = self.findNearestValidPosition(point: pos2D, polygon: polygon) {
                                entity.position.x = validPos.x
                                entity.position.z = validPos.y
                            }
                        }
                    }
                }
            }
            return
        }
        
        guard let result = arView.raycast(from: tapLocation, allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
                  print("Tap: No horizontal plane found.")
                  return
              }
        
        guard let selectedName = self.selectedFurniture,
              let _ = furnitureAssets[selectedName] else {
            print("Tap: No furniture selected in palette.")
            return
        }
        
        isPlacingFurniture = true

        
        let position = SIMD3<Float>(result.worldTransform.columns.3.x,
                                    result.worldTransform.columns.3.y,
                                    result.worldTransform.columns.3.z)
        
        placeFurniture(name: selectedName, position: position, rotation: 0, in: furnitureAnchor)
        self.addItemToCart(category: selectedName)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                  self.isPlacingFurniture = false
                  print("✅ Ready for next placement")
              }
    }
    
    private func findNearestValidPosition(point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> SIMD2<Float>? {
        let center = getPolygonCenter(polygon: polygon)
        let directionToCenter = normalize(center - point)
        
        for i in 1...20 {
            let distance = Float(i) * 0.1
            let candidate = point + directionToCenter * distance
            
            if isPointInPolygonWithMargin(point: candidate, polygon: polygon, margin: 0.5) &&
               !isNearDoor(position: candidate, doors: doorLocations, clearanceRadius: 2.0) {
                return candidate
            }
        }
        
        return nil
    }
    
    private func getFloorPolygon() -> [SIMD2<Float>]? {
        guard let floorElement = structuralElements.first(where: { $0.type == "floor" }),
              let polygonData = floorElement.polygon else { return nil }
        
        return polygonData.map { SIMD2<Float>($0[0], $0[1]) }
    }
    
    private func showBoundaryWarning(message: String) {
        DispatchQueue.main.async {
            self.boundaryWarningMessageBinding?.wrappedValue = message
            self.showBoundaryWarningBinding?.wrappedValue = true
        }
    }
    private func getFloorHeight() -> Float {
         // Try to get floor height from structural elements
         if let floorElement = structuralElements.first(where: { $0.type == "floor" }) {
             let floorY = (floorElement.minBounds[1] + floorElement.maxBounds[1]) / 2.0
             print("📏 Floor height from elements: \(floorY)")
             return floorY
         }
         
         // Fallback to room bounds
         if let bounds = roomBounds {
             let floorY = bounds.minBounds.y
             print("📏 Floor height from bounds: \(floorY)")
             return floorY
         }
         
         // Default fallback
         print("⚠️ Using default floor height: 0.0")
         return 0.0
     }
}

extension BoundingBox {
    func toMDLAxisAlignedBoundingBox() -> MDLAxisAlignedBoundingBox {
        return MDLAxisAlignedBoundingBox(maxBounds: self.max, minBounds: self.min)
    }
}

// ============================================================================
// AI GENERATION EXTENSION
// ============================================================================
extension ARCoordinator {
    
    func generateDesignFromPrompt(_ prompt: String, from scanURL: URL, completion: @escaping ([PlacedFurniture]?) -> Void) {
        print("\n🎨 GENERATING DESIGN FROM PROMPT\n")
        
        guard let roomEntity = try? Entity.load(contentsOf: scanURL) else {
            print("❌ ERROR: Could not load entity from scanURL: \(scanURL)")
            completion(nil)
            return
        }

        print("📐 Processing room geometry...")
        let roomResult = processLoadedRoom(entity: roomEntity)
        let roomBounds = roomResult.overallBounds
        let elements = roomResult.elements
        print("✅ Room bounds: min=\(roomBounds.min), max=\(roomBounds.max)")
        
        let doors = extractDoorLocations(from: elements)
        self.doorLocations = doors
        
        var doorZonesDescription = ""
        if !doors.isEmpty {
            doorZonesDescription = "\n\n**DOOR EXCLUSION ZONES:**\n"
            for (index, door) in doors.enumerated() {
                let exclusionRadius: Float = 2.0
                doorZonesDescription += """
                Door \(index + 1): Center at (\(String(format: "%.2f", door.position.x)), \(String(format: "%.2f", door.position.y)))
                - DO NOT place furniture within \(exclusionRadius)m radius of this point
                - Minimum clearance: \(exclusionRadius)m
                
                """
            }
        }
        
        guard let floorElement = elements.first(where: { $0.type == "floor" }),
              let floorPolygonData = floorElement.polygon else {
            print("❌ ERROR: No floor found")
            completion(nil)
            return
        }
        
        var floorPolygon = floorPolygonData.map { SIMD2<Float>($0[0], $0[1]) }
        var polygonArea = getPolygonArea(polygon: floorPolygon)
        
        if polygonArea < 1.0 {
            print("⚠️ WARNING: Floor polygon area is too small")
            print("🔧 Using rectangular fallback...")
            
            let margin: Float = 0.5
            let minX = roomBounds.min.x + margin
            let maxX = roomBounds.max.x - margin
            let minZ = roomBounds.min.z + margin
            let maxZ = roomBounds.max.z - margin
            
            floorPolygon = [
                SIMD2<Float>(minX, minZ),
                SIMD2<Float>(maxX, minZ),
                SIMD2<Float>(maxX, maxZ),
                SIMD2<Float>(minX, maxZ)
            ]
            
            polygonArea = (maxX - minX) * (maxZ - minZ)
        }
        
        let polygonBounds = getPolygonBounds(polygon: floorPolygon)
        let polygonCenter = getPolygonCenter(polygon: floorPolygon)
        let floorHeight = (floorElement.minBounds[1] + floorElement.maxBounds[1]) / 2.0
        
        let safeMargin: Float = 0.5
        let safeMinX = polygonBounds.min.x + safeMargin
        let safeMaxX = polygonBounds.max.x - safeMargin
        let safeMinZ = polygonBounds.min.y + safeMargin
        let safeMaxZ = polygonBounds.max.y - safeMargin
        
        let systemPrompt = """
        You are an expert interior designer AI with advanced spatial awareness and aesthetic sense.

        **CRITICAL RULES:**
        1. ALL furniture MUST be INSIDE the floor polygon
        2. ALL furniture MUST be at least 0.5 meters from walls
        3. NEVER place furniture within 2.0 meters of any door entrance
        4. DO NOT include Painting or Wall_Clock in your response - these will be added separately

        **FURNITURE RELATIONSHIPS:**
        - Study Desk → MUST have Office Chair in front (0.6-0.8m distance)
        - Sofa → Often has Table nearby (1.0-1.5m distance)
        - Bed → May have Table as nightstand (0.5-0.8m)

        **SPACING REQUIREMENTS:**
        - Large furniture: 1.5-2.0m (Sofa, Bed, Wardrobe)
        - Medium furniture: 1.2-1.5m (Bookshelf, Desk)
        - Wall clearance: 0.5m minimum

        **WALL ALIGNMENT:**
        - Sofa, Bed, Bookshelf, Wardrobe: MUST be against walls
        - Use rotation: 0, 90, 180, or 270 degrees ONLY

        **OUTPUT FORMAT:**
        Return ONLY valid JSON array. Each item: category, position_x, position_z, rotation_y
        """
        
        let userQuery = """
        **USER REQUEST:** '\(prompt)'

        **ROOM CONSTRAINTS:**
        - X-axis range: \(String(format: "%.2f", safeMinX)) to \(String(format: "%.2f", safeMaxX)) meters
        - Z-axis range: \(String(format: "%.2f", safeMinZ)) to \(String(format: "%.2f", safeMaxZ)) meters
        - Room center: (\(String(format: "%.2f", polygonCenter.x)), \(String(format: "%.2f", polygonCenter.y)))
        - Floor area: \(String(format: "%.2f", polygonArea)) m²
        \(doorZonesDescription)

        Generate furniture layout respecting ALL constraints above.
        DO NOT include Painting or Wall_Clock.
        """
        
        let apiKey = "AIzaSyClvAPSXDweflBx4HyHCD7StHop6i3xojY"
        let apiUrl = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=\(apiKey)"
        
        let schema = """
        {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "category": { "type": "string" },
              "position_x": { "type": "number" },
              "position_z": { "type": "number" },
              "rotation_y": { "type": "number" }
            },
            "required": ["category", "position_x", "position_z", "rotation_y"]
          }
        }
        """
        
        let payload: [String: Any] = [
            "contents": [["parts": [["text": userQuery]]]],
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": try! JSONSerialization.jsonObject(with: schema.data(using: .utf8)!, options: [])
            ]
        ]
        
        var request = URLRequest(url: URL(string: apiUrl)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        Task {
            do {
                print("🌐 Calling Gemini AI...")
                let (data, _) = try await URLSession.shared.data(for: request)
                
                print("--- RAW GEMINI RESPONSE --- \n\(String(data: data, encoding: .utf8) ?? "No data")\n---------------------------")
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String:Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    print("❌ ERROR: Could not parse Gemini response")
                    throw URLError(.cannotParseResponse)
                }
                
                let responseJsonData = text.data(using: .utf8)!
                let llmResponse = try JSONDecoder().decode([LLMPlacementResponse].self, from: responseJsonData)
                
                print("\n🤖 AI GENERATED \(llmResponse.count) ITEMS")
                
                // Convert to PlacedFurniture
                var layout = llmResponse.map { item in
                    PlacedFurniture(
                        position: SIMD3<Float>(item.position_x, 0.0, item.position_z),
                        rotation: item.rotation_y,
                        category: item.category
                    )
                }
                
                // Filter out wall items
                let wallDecorations = ["Painting", "Wall_Clock", "Wall Clock"]
                let originalCount = layout.count
                layout = layout.filter { !wallDecorations.contains($0.category) }
                let filteredCount = originalCount - layout.count

                if filteredCount > 0 {
                    print("🚫 Filtered out \(filteredCount) wall decorations")
                }

                print("\n🔍 VALIDATING FURNITURE POSITIONS...")
                
                // Validate and fix layout
                layout = validateAndFixLayoutWithDoors(
                    layout: layout,
                    polygon: floorPolygon,
                    doors: doors,
                    margin: 0.5,
                    doorClearance: 2.5
                )
                
                layout = normalizeRotations(layout: layout)
                layout = ensureProperSpacing(layout: layout, polygon: floorPolygon)
                layout = alignFurnitureToWalls(layout: layout, polygon: floorPolygon)
                layout = ensureTablesHaveChairs(layout: layout, polygon: floorPolygon)
                layout = placePotsOnTables(layout: layout)
                
                // Process with metadata
                layout = processLayoutWithMetadata(
                    layout: layout,
                    polygon: floorPolygon,
                    floorHeight: floorHeight,
                    rotationStrategy: "smart"
                )
                
                // Apply collision avoidance
                layout = placeWithCollisionAvoidance(
                    layout: layout,
                    polygon: floorPolygon
                )
                
                // Add wall decorations manually
                layout = addWallDecorationsManually(
                    to: layout,
                    polygon: floorPolygon,
                    floorHeight: floorHeight
                )

                print("\n✅ Final layout: \(layout.count) items")
                
                // Update cart
                let newCart = layout.reduce(into: [String: Int]()) { counts, item in
                    counts[item.category, default: 0] += 1
                }
                
                DispatchQueue.main.async {
                    self.furnitureCart = newCart
                    self.updateTotalPrice()
                    completion(layout)
                }
                
            } catch {
                print("❌ ERROR calling Gemini: \(error)")
                DispatchQueue.main.async {
                    self.furnitureCart = [:]
                    self.updateTotalPrice()
                    completion(nil)
                }
            }
        }
    }
    
    
    struct LLMPlacementResponse: Codable {
        let category: String
        let position_x: Float
        let position_z: Float
        let rotation_y: Float
    }
}

// ============================================================================
// VALIDATION WITH DOOR CHECKING
// ============================================================================
func validateAndFixLayoutWithDoors(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    doors: [DoorInfo],
    margin: Float = 0.5,
    doorClearance: Float = 2.0
) -> [PlacedFurniture] {
    
    var validatedLayout: [PlacedFurniture] = []
    var invalidCount = 0
    
    for item in layout {
        let pos2D = SIMD2<Float>(item.position.x, item.position.z)
        
        guard isPointInPolygonWithMargin(point: pos2D, polygon: polygon, margin: margin) else {
            print("❌ \(item.category) OUTSIDE safe zone")
            
            if let validPos = findNearestValidPositionAvoidingDoors(
                point: pos2D,
                polygon: polygon,
                doors: doors,
                margin: margin,
                doorClearance: doorClearance
            ) {
                print("✅ CORRECTED position")
                validatedLayout.append(PlacedFurniture(
                    position: SIMD3<Float>(validPos.x, item.position.y, validPos.y),
                    rotation: item.rotation,
                    category: item.category
                ))
            } else {
                print("🚫 REMOVED - no valid position")
                invalidCount += 1
            }
            continue
        }
        
        if isNearDoor(position: pos2D, doors: doors, clearanceRadius: doorClearance) {
            print("🚪 \(item.category) TOO CLOSE to door")
            
            if let validPos = findNearestValidPositionAvoidingDoors(
                point: pos2D,
                polygon: polygon,
                doors: doors,
                margin: margin,
                doorClearance: doorClearance
            ) {
                print("✅ MOVED away from door")
                validatedLayout.append(PlacedFurniture(
                    position: SIMD3<Float>(validPos.x, item.position.y, validPos.y),
                    rotation: item.rotation,
                    category: item.category
                ))
            } else {
                print("🚫 REMOVED - too close to door")
                invalidCount += 1
            }
            continue
        }
        
        print("✅ \(item.category) VALID")
        validatedLayout.append(item)
    }
    
    if invalidCount > 0 {
        print("\n⚠️ Removed \(invalidCount) invalid items")
    }
    
    return validatedLayout
}

func findNearestValidPositionAvoidingDoors(
    point: SIMD2<Float>,
    polygon: [SIMD2<Float>],
    doors: [DoorInfo],
    margin: Float = 0.5,
    doorClearance: Float = 2.0
) -> SIMD2<Float>? {
    
    let center = getPolygonCenter(polygon: polygon)
    let directionToCenter = normalize(center - point)
    
    for i in 1...50 {
        let distance = Float(i) * 0.2
        let candidate = point + directionToCenter * distance
        
        if isPointInPolygonWithMargin(point: candidate, polygon: polygon, margin: margin) &&
           !isNearDoor(position: candidate, doors: doors, clearanceRadius: doorClearance) {
            return candidate
        }
    }
    
    let angleStep: Float = 30 * .pi / 180
    let radiusStep: Float = 0.3
    
    for radius in stride(from: radiusStep, through: 3.0, by: radiusStep) {
        for angle in stride(from: Float(0), to: 2 * .pi, by: angleStep) {
            let offset = SIMD2<Float>(cos(angle), sin(angle)) * radius
            let candidate = point + offset
            
            if isPointInPolygonWithMargin(point: candidate, polygon: polygon, margin: margin) &&
               !isNearDoor(position: candidate, doors: doors, clearanceRadius: doorClearance) {
                return candidate
            }
        }
    }
    
    return nil
}

// ============================================================================
// ROTATION NORMALIZATION
// ============================================================================
func normalizeRotations(layout: [PlacedFurniture]) -> [PlacedFurniture] {
    let largeFurniture = ["Sofa", "Bed", "Bookshelf", "Wardrobe", "Dressing_Table", "Study Desk"]
    
    return layout.map { item in
        if largeFurniture.contains(item.category) {
            let normalizedRotation = round(item.rotation / 90.0) * 90.0
            print("🔄 Normalized \(item.category) rotation: \(normalizedRotation)°")
            
            return PlacedFurniture(
                position: item.position,
                rotation: normalizedRotation,
                category: item.category
            )
        }
        return item
    }
}

// ============================================================================
// SPACING ENFORCEMENT
// ============================================================================
func ensureProperSpacing(layout: [PlacedFurniture], polygon: [SIMD2<Float>]) -> [PlacedFurniture] {
    var adjustedLayout: [PlacedFurniture] = []
    
    func getMinSpacing(category: String) -> Float {
        switch category {
        case "Sofa", "Bed", "Wardrobe":
            return 2.0  // Increased from 1.5
        case "Table", "Study Desk", "Bookshelf", "Dressing_Table":
            return 1.5  // Increased from 1.2
        default:
            return 1.0  // Increased from 0.8
        }
    }
    
    for item in layout {
        var position2D = SIMD2<Float>(item.position.x, item.position.z)
        var needsAdjustment = false
        
        for placedItem in adjustedLayout {
            let placedPos2D = SIMD2<Float>(placedItem.position.x, placedItem.position.z)
            let distance = length(position2D - placedPos2D)
            let requiredSpacing = max(getMinSpacing(category: item.category), getMinSpacing(category: placedItem.category))
            
            if distance < requiredSpacing {
                needsAdjustment = true
                print("⚠️ \(item.category) too close to \(placedItem.category)")
                
                let direction = normalize(position2D - placedPos2D)
                position2D = placedPos2D + direction * (requiredSpacing + 0.3)
                
                if !isPointInPolygonWithMargin(point: position2D, polygon: polygon, margin: 0.5) {
                    position2D = placedPos2D - direction * (requiredSpacing + 0.3)
                    
                    if !isPointInPolygonWithMargin(point: position2D, polygon: polygon, margin: 0.5) {
                        print("🚫 Cannot find valid spacing for \(item.category)")
                        continue
                    }
                }
            }
        }
        
        if needsAdjustment {
            print("✅ Adjusted \(item.category) position")
        }
        
        adjustedLayout.append(PlacedFurniture(
            position: SIMD3<Float>(position2D.x, item.position.y, position2D.y),
            rotation: item.rotation,
            category: item.category
        ))
    }
    
    print("\n✅ SPACING CHECK: \(adjustedLayout.count) of \(layout.count) items placed")
    return adjustedLayout
}
func ensureTablesHaveChairs(layout: [PlacedFurniture], polygon: [SIMD2<Float>]) -> [PlacedFurniture] {
    var updatedLayout = layout
    
    let tables = layout.filter {
        $0.category == "Table" || $0.category == "Study Desk"
    }
    
    for table in tables {
        // Check if chairs exist near this table
        let tablePos = SIMD2<Float>(table.position.x, table.position.z)
        
        let nearbyChairs = layout.filter { item in
            guard item.category == "Office Chair" else { return false }
            let chairPos = SIMD2<Float>(item.position.x, item.position.z)
            let distance = length(tablePos - chairPos)
            return distance < 1.5
        }
        
        // If no chairs near table, add chairs
        if nearbyChairs.isEmpty {
            let chairCount = table.category == "Study Desk" ? 1 : 2
            let chairDistance: Float = 0.7
            
            for i in 0..<chairCount {
                let angle = Float(i) * (360.0 / Float(chairCount)) * .pi / 180.0
                let offset = SIMD2<Float>(cos(angle), sin(angle)) * chairDistance
                let chairPos2D = tablePos + offset
                
                // Check if position is valid
                if isPointInPolygonWithMargin(point: chairPos2D, polygon: polygon, margin: 0.5) {
                    let chairRotation = atan2(offset.y, offset.x) * 180.0 / .pi + 180.0
                    
                    updatedLayout.append(PlacedFurniture(
                        position: SIMD3<Float>(chairPos2D.x, 0.0, chairPos2D.y),
                        rotation: chairRotation,
                        category: "Office Chair"
                    ))
                    
                    print("✅ Added Office Chair near \(table.category)")
                }
            }
        }
    }
    
    return updatedLayout
}

// ============================================================================
// FIX 8: PLACE SMALL POTS ON TABLES (Post-processing)
// ============================================================================

func placePotsOnTables(layout: [PlacedFurniture]) -> [PlacedFurniture] {
    var updatedLayout = layout
    
    let pots = layout.filter { $0.category == "Pot" }
    let tables = layout.filter { $0.category == "Table" }
    
    guard !pots.isEmpty && !tables.isEmpty else { return layout }
    
    for pot in pots {
        if let nearestTable = tables.min(by: { table1, table2 in
            let dist1 = length(SIMD2<Float>(pot.position.x, pot.position.z) -
                             SIMD2<Float>(table1.position.x, table1.position.z))
            let dist2 = length(SIMD2<Float>(pot.position.x, pot.position.z) -
                             SIMD2<Float>(table2.position.x, table2.position.z))
            return dist1 < dist2
        }) {
            let tablePos = nearestTable.position
            
            // Place pot on table (slightly offset)
            let offsetX = Float.random(in: -0.2...0.2)
            let offsetZ = Float.random(in: -0.2...0.2)
            
            if let index = updatedLayout.firstIndex(where: {
                $0.category == pot.category &&
                $0.position == pot.position
            }) {
                updatedLayout[index] = PlacedFurniture(
                    position: SIMD3<Float>(
                        tablePos.x + offsetX,
                        tablePos.y + 0.5,  // On table surface
                        tablePos.z + offsetZ
                    ),
                    rotation: Float.random(in: 0...360),
                    category: "Pot"
                )
                
                print("✅ Placed Pot on Table")
            }
        }
    }
    
    return updatedLayout
}

// ============================================================================
// FIX 3: ALIGN LARGE FURNITURE TO WALLS
// ============================================================================

func alignFurnitureToWalls(
    layout: [PlacedFurniture],
    polygon: [SIMD2<Float>]
) -> [PlacedFurniture] {
    
    let largeFurniture = ["Sofa", "Bed", "Bookshelf", "Wardrobe", "Dressing_Table", "Study Desk"]
    
    return layout.map { item in
        guard largeFurniture.contains(item.category) else { return item }
        
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
        
        // Snap to nearest 90-degree angle
        let normalizedAngle = round(wallAngle / 90.0) * 90.0
        
        // Position furniture close to wall (0.3m from wall)
        let wallNormal = SIMD2<Float>(-wallDirection.y, wallDirection.x)
        let normalizedNormal = normalize(wallNormal)
        let newPos2D = pos2D + normalizedNormal * 0.3
        
        print("🔄 Aligned \(item.category) to wall at \(normalizedAngle)°")
        
        return PlacedFurniture(
            position: SIMD3<Float>(newPos2D.x, item.position.y, newPos2D.y),
            rotation: normalizedAngle + 90.0,  // Face into room
            category: item.category
        )
    }
}

func distanceToLineSegment(point: SIMD2<Float>, lineStart: SIMD2<Float>, lineEnd: SIMD2<Float>) -> Float {
    let line = lineEnd - lineStart
    let lineLength = length(line)
    
    guard lineLength > 0.001 else {
        return length(point - lineStart)
    }
    
    let t = max(0, min(1, dot(point - lineStart, line) / (lineLength * lineLength)))
    let projection = lineStart + line * t
    
    return length(point - projection)
}
func addWallDecorationsManually(
    to layout: [PlacedFurniture],
    polygon: [SIMD2<Float>],
    floorHeight: Float
) -> [PlacedFurniture] {
    
    print("\n🖼️ Manually adding wall decorations...")
    
    var result = layout
    
    // Extract wall segments
    let walls = extractWallSegments(from: polygon)
    guard walls.count >= 2 else {
        print("⚠️ Need at least 2 walls for painting and clock")
        return result
    }
    
    // Sort walls by length (longest first)
    let sortedWalls = walls.sorted { $0.length > $1.length }
    
    // Select two opposite or different walls
    let paintingWall = sortedWalls[0]  // Longest wall
    let clockWall = sortedWalls.count >= 3 ? sortedWalls[2] : sortedWalls[1]  // Different wall
    
    // === PLACE PAINTING ===
    let paintingHeight: Float = 1.5  // Eye level
    let paintingPosition2D = paintingWall.midpoint + paintingWall.normal * 0.05
    let paintingPosition = SIMD3<Float>(
        paintingPosition2D.x,
        floorHeight + paintingHeight,
        paintingPosition2D.y
    )
    let paintingRotation = paintingWall.angle + 90.0
    
    let painting = PlacedFurniture(
        position: paintingPosition,
        rotation: paintingRotation,
        category: "Painting"
    )
    result.append(painting)
    print("  ✅ Added Painting on wall 1 at height \(floorHeight + paintingHeight)")
    
    // === PLACE CLOCK ===
    let clockHeight: Float = 2.0  // Above eye level
    let clockPosition2D = clockWall.midpoint + clockWall.normal * 0.05
    let clockPosition = SIMD3<Float>(
        clockPosition2D.x,
        floorHeight + clockHeight,
        clockPosition2D.y
    )
    let clockRotation = clockWall.angle + 90.0
    
    let clock = PlacedFurniture(
        position: clockPosition,
        rotation: clockRotation,
        category: "Wall_Clock"
    )
    result.append(clock)
    print("  ✅ Added Wall_Clock on wall 2 at height \(floorHeight + clockHeight)")
    
    return result
}

