import SwiftUI
import RealityKit
import ARKit
import UIKit
import ModelIO
import Combine

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
        wallColors: [UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)],
        floorColor: UIColor(red: 0.8, green: 0.75, blue: 0.68, alpha: 1.0),
        name: "Modern"
    ),
    "warm": RoomTheme(
        wallColors: [UIColor(red: 0.98, green: 0.94, blue: 0.85, alpha: 1.0)],
        floorColor: UIColor(red: 0.65, green: 0.45, blue: 0.30, alpha: 1.0),
        name: "Warm"
    ),
    "cool": RoomTheme(
        wallColors: [UIColor(red: 0.88, green: 0.92, blue: 0.95, alpha: 1.0)],
        floorColor: UIColor(red: 0.7, green: 0.7, blue: 0.75, alpha: 1.0),
        name: "Cool"
    )
]

func detectThemeFromPrompt(_ prompt: String) -> RoomTheme {
    let lowercased = prompt.lowercased()
    
    if lowercased.contains("warm") || lowercased.contains("cozy") {
        return predefinedThemes["warm"]!
    }
    if lowercased.contains("cool") || lowercased.contains("calm") {
        return predefinedThemes["cool"]!
    }
    return predefinedThemes["modern"]!
}

func applyThemeToRoom(roomEntity: Entity, theme: RoomTheme) {
    print("🎨 Applying \(theme.name) theme to room...")
    
    func applyThemeRecursive(entity: Entity) {
        let name = entity.name.lowercased()
        
        if name.contains("floor"), let modelEntity = entity as? ModelEntity, let floorColor = theme.floorColor {
            var material = SimpleMaterial()
            material.baseColor = .color(floorColor)
            material.roughness = 0.8
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
    var selectedEntity: Entity? = nil
    private var dragStartPosition: SIMD3<Float>? = nil
    
    var showBoundaryWarningBinding: Binding<Bool>?
    var boundaryWarningMessageBinding: Binding<String>?
    var showDeleteConfirmationBinding: Binding<Bool>?
    var furnitureToDeleteBinding: Binding<Entity?>?
    
    @Published var sceneLoadError: String? = nil
    @Published var selectedFurniture: String? = nil
    @Published var furnitureCart: [String: Int] = [:]
    @Published var totalPrice: Float = 0.0
    @Published var availableFurniture: [FurnitureItem] = []
    @Published var isLoadingFurniture: Bool = false
    @Published var furnitureWithMetadata: [PlacedFurnitureWithMetadata] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var totalFurnitureToLoad: Int = 0
    @Published var furnitureLoaded: Int = 0
    
    private var isPlacingFurniture = false
    private var furnitureByCategory: [String: [FurnitureItem]] = [:]
    
    // ============================================================================
    // ROOM LOADING
    // ============================================================================
    
    func loadRoomBounds(from url: URL) {
        guard roomBounds == nil else { return }
        
        guard let roomEntity = try? Entity.load(contentsOf: url) else {
            self.sceneLoadError = "Failed to load room from URL."
            return
        }
        
        let analysis = processLoadedRoom(entity: roomEntity)
        self.roomBounds = analysis.overallBounds.toMDLAxisAlignedBoundingBox()
        self.structuralElements = analysis.elements
        print("✅ Room bounds and \(analysis.elements.count) structural elements loaded.")
    }
    
    func findDraggableParent(from entity: Entity) -> Entity? {
        if entity.name.starts(with: "FURN_") {
            return entity
        }
        if let parent = entity.parent {
            return findDraggableParent(from: parent)
        }
        return nil
    }
    
    func reloadFurnitureInPreview(_ layout: [PlacedFurniture], in anchor: Entity) {
        print("\n🔄 Reloading furniture in preview...")
        
        anchor.children.forEach { child in
            if child.name.starts(with: "FURN_") {
                child.removeFromParent()
            }
        }
        
        placeFurnitureList(layout, in: anchor, isPreview: true)
        
        print("✅ Preview reloaded with \(layout.count) items")
    }
    
    // MARK: - Sync Layout from AR
    func syncLayoutFromAR(_ layout: [PlacedFurniture]) {
        print("\n🔄 Syncing layout from AR...")
        
        let layoutWithMetadata = matchLayoutWithFurniture(
            layout: layout,
            furnitureItems: availableFurniture
        )
        
        self.furnitureWithMetadata = layoutWithMetadata
        updateCartFromLayout(layoutWithMetadata)
        
        print("✅ Sync complete: \(layoutWithMetadata.count) items, $\(String(format: "%.2f", totalPrice))")
    }
    
    // ============================================================================
    // GESTURE HANDLERS
    // ============================================================================
    
    func setupARGestures(for arView: ARView) {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(panGesture)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        arView.addGestureRecognizer(longPressGesture)
        
        print("✅ AR gestures configured")
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        
        let location = gesture.location(in: arView)
        
        // Remove previous selection highlight
        if let selected = selectedEntity {
            removeHighlight(from: selected)
        }
        
        // Check if we tapped on furniture
        if let entity = arView.entity(at: location) {
            if let furniture = findDraggableParent(from: entity) {
                selectedEntity = furniture
                addHighlight(to: furniture)
                
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                
                print("✅ Selected: \(furniture.name)")
                return
            }
        }
        
        // If we get here, we didn't tap furniture
        selectedEntity = nil
        print("ℹ️ Deselected")
    }
    
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let arView = arView,
              let selected = selectedEntity else { return }
        
        let location = gesture.location(in: arView)
        
        switch gesture.state {
        case .began:
            dragStartPosition = selected.position
            print("🎯 Started dragging: \(selected.name)")
            
        case .changed:
            let results = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal)
            
            guard let result = results.first else { return }
            
            let newPosition = result.worldTransform.columns.3
            let pos2D = SIMD2<Float>(newPosition.x, newPosition.z)
            
            // Check if within room boundaries
            if let floorElement = structuralElements.first(where: { $0.type == "floor" }),
               let polygonData = floorElement.polygon {
                let polygon = polygonData.map { SIMD2<Float>($0[0], $0[1]) }
                
                if isPointInPolygonWithMargin(point: pos2D, polygon: polygon, margin: 0.3) {
                    // Valid position - update furniture location
                    selected.position = SIMD3<Float>(newPosition.x, selected.position.y, newPosition.z)
                } else {
                    // Outside boundaries - show warning
                    showBoundaryWarningBinding?.wrappedValue = true
                    boundaryWarningMessageBinding?.wrappedValue = "⚠️ Cannot place furniture outside room boundaries"
                    
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                }
            }
            
        case .ended, .cancelled:
            dragStartPosition = nil
            print("✅ Finished dragging: \(selected.name)")
            
        default:
            break
        }
    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let arView = arView else { return }
        
        let location = gesture.location(in: arView)
        
        if let entity = arView.entity(at: location),
           let furniture = findDraggableParent(from: entity) {
            
            // Trigger delete confirmation
            furnitureToDeleteBinding?.wrappedValue = furniture
            showDeleteConfirmationBinding?.wrappedValue = true
            
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            
            print("🗑️ Long press detected on: \(furniture.name)")
        }
    }
    
    private func addHighlight(to entity: Entity) {
        entity.scale *= 1.1
    }
    
    private func removeHighlight(from entity: Entity) {
        entity.scale /= 1.1
    }
    
    // ============================================================================
    // DELETE FURNITURE
    // ============================================================================
    
    func deleteFurniture(_ furniture: Entity) {
        print("🗑️ Deleting \(furniture.name)")
        
        // Extract category from furniture name (format: "FURN_0_ItemName")
        if let category = extractCategoryFromFurnitureName(furniture.name) {
            removeItemFromCart(category: category)
        }
        
        furniture.removeFromParent()
        
        // Clear selection if this was the selected entity
        if selectedEntity == furniture {
            selectedEntity = nil
        }
    }
    
    private func extractCategoryFromFurnitureName(_ name: String) -> String? {
        // Name format: "FURN_0_Modern_Sofa_Set" or "FURN_0_ItemName"
        let components = name.components(separatedBy: "_")
        
        if components.count >= 3 {
            // Reconstruct the item name from components after "FURN" and index
            let itemNameParts = components.dropFirst(2)
            
            // Try to find matching furniture in our metadata
            if let matchingFurniture = furnitureWithMetadata.first(where: {
                $0.metadata.itemName.replacingOccurrences(of: " ", with: "_") == itemNameParts.joined(separator: "_")
            }) {
                return matchingFurniture.metadata.category
            }
        }
        
        return nil
    }
    
    // ============================================================================
    // MAIN ENTRY POINT: Generate Design with Search (FIXED)
    // ============================================================================
    
    func generateDesignWithSearch(_ prompt: String, from url: URL, completion: @escaping ([PlacedFurniture]?) -> Void) {
        print("\n" + String(repeating: "=", count: 80))
        print("🎨 STARTING DESIGN GENERATION")
        print("   Prompt: '\(prompt)'")
        print(String(repeating: "=", count: 80) + "\n")
        
        Task { @MainActor in
            // STEP 1: Call LLM Search API to get furniture
            print("📞 STEP 1: Calling LLM Search API...")
            guard let searchData = await callSearchAPI(macIP: getMacIP(), prompt: prompt) else {
                print("❌ LLM search API failed")
                completion(nil)
                return
            }
            
            // DEBUG: Print Raw JSON
            if let jsonString = String(data: searchData, encoding: .utf8) {
                print("🔍 RAW JSON: \(jsonString)")
            }
            
            do {
                let decoder = JSONDecoder()
                // decoder.keyDecodingStrategy = .convertFromSnakeCase // Use if needed
                
                // STEP 2: Parse furniture response
                // NOTE: Ensure FurnitureSearchResponse is available in your project
                let furnitureResponse = try decoder.decode(FurnitureSearchResponse.self, from: searchData)
                
                // ✅ NULL CHECK: If no furniture returned, don't proceed
                guard !furnitureResponse.results.isEmpty else {
                    print("⚠️ LLM returned 0 furniture items - cannot proceed")
                    print("💡 Try a different prompt or check your search API")
                    completion(nil)
                    return
                }
                
                print("✅ LLM returned \(furnitureResponse.results.count) furniture items")
                for item in furnitureResponse.results.prefix(5) {
                    print("   - \(item.itemName) (\(item.category), $\(item.price))")
                }
                if furnitureResponse.results.count > 5 {
                    print("   ... and \(furnitureResponse.results.count - 5) more")
                }
                
                // ===============================================================
                // 🚀 LOGIC MOVED INSIDE DO-BLOCK TO FIX SCOPE ERROR
                // ===============================================================
                
                // STEP 3: Store furniture data
                print("\n💾 STEP 3: Storing furniture data...")
                self.availableFurniture = furnitureResponse.results
                self.furnitureByCategory = Dictionary(grouping: furnitureResponse.results) { $0.category }
                print("✅ Stored \(self.furnitureByCategory.keys.count) unique categories")
                
                // STEP 4: Call Gemini to place furniture
                print("\n🤖 STEP 4: Calling Gemini for placement...")
                guard let placementLayout = await callGeminiForPlacement(
                    furnitureItems: furnitureResponse.results,
                    prompt: prompt,
                    roomURL: url
                ) else {
                    print("❌ Gemini placement failed")
                    completion(nil)
                    return
                }
                
                // STEP 5: Match placements with furniture metadata
                print("\n🔗 STEP 5: Matching placements with furniture metadata...")
                let layoutWithMetadata = matchLayoutWithFurniture(
                    layout: placementLayout,
                    furnitureItems: furnitureResponse.results
                )
                
                self.furnitureWithMetadata = layoutWithMetadata
                print("✅ Matched \(layoutWithMetadata.count) items")
                
                // STEP 6: Update cart
                print("\n🛒 STEP 6: Updating shopping cart...")
                updateCartFromLayout(layoutWithMetadata)
                
                print("\n" + String(repeating: "=", count: 80))
                print("✅ DESIGN GENERATION COMPLETE")
                print("   Total items: \(placementLayout.count)")
                print("   Total price: $\(String(format: "%.2f", self.totalPrice))")
                print(String(repeating: "=", count: 80) + "\n")
                
                completion(placementLayout)
                
            } catch let DecodingError.dataCorrupted(context) {
                print("❌ Data corrupted: \(context)")
                completion(nil)
            } catch let DecodingError.keyNotFound(key, context) {
                print("❌ Key '\(key)' not found: \(context.debugDescription)")
                print("   (Check if your backend JSON key matches the Swift struct property)")
                completion(nil)
            } catch let DecodingError.valueNotFound(value, context) {
                print("❌ Value '\(value)' not found: \(context.debugDescription)")
                completion(nil)
            } catch let DecodingError.typeMismatch(type, context) {
                print("❌ Type mismatch: \(type), \(context.debugDescription)")
                print("   (Did the backend send a String where you expected a Float?)")
                completion(nil)
            } catch {
                print("❌ Unknown error: \(error)")
                completion(nil)
            }
        }
    }
    
    // ============================================================================
    // CALL GEMINI FOR PLACEMENT
    // ============================================================================
    
    private func callGeminiForPlacement(
        furnitureItems: [FurnitureItem],
        prompt: String,
        roomURL: URL
    ) async -> [PlacedFurniture]? {
        
        // Load room to get floor polygon
        guard let roomEntity = try? Entity.load(contentsOf: roomURL) else {
            print("❌ Failed to load room for placement")
            return nil
        }
        
        let analysis = processLoadedRoom(entity: roomEntity)
        
        guard let floorElement = analysis.elements.first(where: { $0.type == "floor" }),
              let polygonData = floorElement.polygon else {
            print("❌ No floor polygon found")
            return nil
        }
        
        let polygon = polygonData.map { SIMD2<Float>($0[0], $0[1]) }
        let bounds = getPolygonBounds(polygon: polygon)
        let floorHeight = floorElement.minBounds[1]
        
        print("📐 Room constraints:")
        print("   Floor height: \(floorHeight)m")
        print("   Bounds: X[\(bounds.min.x), \(bounds.max.x)], Z[\(bounds.min.y), \(bounds.max.y)]")
        print("   Polygon vertices: \(polygon.count)")
        
        // Build Gemini prompt
        let geminiPrompt = buildGeminiPlacementPrompt(
            furnitureItems: furnitureItems,
            userPrompt: prompt,
            bounds: bounds,
            floorHeight: floorHeight,
            polygon: polygon
        )
        
        // Call Gemini API
        guard let placementData = await callGeminiAPI(prompt: geminiPrompt) else {
            print("❌ Gemini API call failed")
            return nil
        }
        
        // Parse response
        guard let layout = parseGeminiPlacementResponse(placementData, furnitureItems: furnitureItems) else {
            print("❌ Failed to parse Gemini response")
            return nil
        }
        
        print("✅ Gemini returned \(layout.count) placements")
        
        // Validate and process layout
        let dimensionsMap = buildDimensionsMap(furnitureItems: furnitureItems, layout: layout)
        
        var processedLayout = validateAndFixLayout(
            layout: layout,
            polygon: polygon,
            margin: 0.4
        )
        
        processedLayout = removeOverlappingFurnitureWithDimensions(
            layout: processedLayout,
            minDistance: 0.2,
            dimensionsMap: dimensionsMap
        )
        
        print("✅ Final validated layout: \(processedLayout.count) items")
        
        return processedLayout
    }
    
    private func buildGeminiPlacementPrompt(
        furnitureItems: [FurnitureItem],
        userPrompt: String,
        bounds: (min: SIMD2<Float>, max: SIMD2<Float>),
        floorHeight: Float,
        polygon: [SIMD2<Float>]
    ) -> String {
        
        var prompt = """
        You are an interior design AI. Place furniture in a room based on these constraints:
        
        USER REQUEST: "\(userPrompt)"
        
        ROOM CONSTRAINTS:
        - Floor height: \(floorHeight) meters
        - X bounds: [\(bounds.min.x), \(bounds.max.x)] meters
        - Z bounds: [\(bounds.min.y), \(bounds.max.y)] meters
        - CRITICAL: All furniture MUST be placed within these bounds with 0.4m margin from walls
        
        AVAILABLE FURNITURE:
        """
        
        for (index, item) in furnitureItems.enumerated() {
            let dims = item.dimensionsInMeters
            prompt += "\n\(index + 1). \(item.itemName)"
            prompt += "\n   - Category: \(item.category)"
            prompt += "\n   - Size: \(dims.x)m x \(dims.y)m x \(dims.z)m (W x H x D)"
            prompt += "\n   - Price: $\(item.price)"
        }
        
        prompt += """
        
        
        PLACEMENT RULES:
        1. ALL positions must be within bounds: X[\(bounds.min.x + 0.4), \(bounds.max.x - 0.4)], Z[\(bounds.min.y + 0.4), \(bounds.max.y - 0.4)]
        2. Leave 0.3-0.5m spacing between furniture
        3. Large furniture (beds, sofas) against walls
        4. Leave pathways for movement
        5. Consider natural groupings (dining set, living area, etc.)
        
        OUTPUT FORMAT (JSON array):
        [
          {
            "category": "<exact category name>",
            "position_x": <x coordinate>,
            "position_y": \(floorHeight),
            "position_z": <z coordinate>,
            "rotation_y": <rotation in degrees 0-360>
          }
        ]
        
        Return ONLY the JSON array, no other text.
        """
        
        return prompt
    }
    
    private func parseGeminiPlacementResponse(_ data: Data, furnitureItems: [FurnitureItem]) -> [PlacedFurniture]? {
        // Try to extract JSON from response
        guard let responseString = String(data: data, encoding: .utf8) else {
            print("❌ Could not decode response as UTF-8")
            return nil
        }
        
        // Remove markdown code blocks if present
        var jsonString = responseString
            .replacingOccurrences(of: "```json\n", with: "")
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "\n```", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to find JSON array
        if let startIndex = jsonString.firstIndex(of: "["),
           let endIndex = jsonString.lastIndex(of: "]") {
            jsonString = String(jsonString[startIndex...endIndex])
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Could not convert cleaned response to data")
            return nil
        }
        
        do {
            let layout = try JSONDecoder().decode([PlacedFurniture].self, from: jsonData)
            print("✅ Parsed \(layout.count) furniture placements")
            return layout
        } catch {
            print("❌ JSON parsing error: \(error)")
            print("Response excerpt: \(jsonString.prefix(500))")
            return nil
        }
    }
    
    // ============================================================================
    // COLLISION DETECTION WITH DIMENSIONS
    // ============================================================================
    
    private func removeOverlappingFurnitureWithDimensions(
        layout: [PlacedFurniture],
        minDistance: Float,
        dimensionsMap: [String: SIMD3<Float>]
    ) -> [PlacedFurniture] {
        
        print("\n🔍 Checking for overlapping furniture...")
        
        var validItems: [PlacedFurniture] = []
        var removedItems: [String] = []
        
        for item in layout {
            let dimensions = dimensionsMap[item.category] ?? SIMD3<Float>(1.0, 1.0, 1.0)
            var hasOverlap = false
            
            // Check for small items that can be closer together
            let isSmallItem = item.category.lowercased().contains("lamp") ||
                            item.category.lowercased().contains("pot") ||
                            item.category.lowercased().contains("plant")
            
            let baseMinDistance: Float = isSmallItem ? 0.2 : minDistance
            
            for existing in validItems {
                let existingDimensions = dimensionsMap[existing.category] ?? SIMD3<Float>(1.0, 1.0, 1.0)
                
                let isExistingSmall = existing.category.lowercased().contains("lamp") ||
                                     existing.category.lowercased().contains("pot") ||
                                     existing.category.lowercased().contains("plant")
                
                // Use smaller distance if both are small items
                let minDist = (isSmallItem && isExistingSmall) ? 0.15 : baseMinDistance
                
                let newBounds = getBounds2D(for: item, dimensions: dimensions)
                let existingBounds = getBounds2D(for: existing, dimensions: existingDimensions)
                
                if checkOverlap(bounds1: newBounds, bounds2: existingBounds, minDistance: minDist) {
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
            print("\n✅ No overlaps detected!")
        }
        
        return validItems
    }
    
    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================
    
    private func buildDimensionsMap(furnitureItems: [FurnitureItem], layout: [PlacedFurniture]) -> [String: SIMD3<Float>] {
        var dimensionsMap: [String: SIMD3<Float>] = [:]
        
        for item in layout {
            if let furnitureData = furnitureItems.first(where: { matchCategory($0.category, item.category) }) {
                dimensionsMap[item.category] = furnitureData.dimensionsInMeters
            }
        }
        
        return dimensionsMap
    }
    
    private func matchLayoutWithFurniture(
        layout: [PlacedFurniture],
        furnitureItems: [FurnitureItem]
    ) -> [PlacedFurnitureWithMetadata] {
        
        return layout.compactMap { placement in
            if let furniture = furnitureItems.first(where: { matchCategory($0.category, placement.category) }) {
                print("   ✅ Matched \(placement.category) → \(furniture.itemName)")
                return PlacedFurnitureWithMetadata(
                    placement: placement,
                    metadata: furniture
                )
            } else {
                print("   ⚠️ No furniture data found for \(placement.category)")
                return nil
            }
        }
    }
    
    func matchCategory(_ apiCategory: String, _ placementCategory: String) -> Bool {
        let normalized1 = apiCategory.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        
        let normalized2 = placementCategory.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        
        let words1 = Set(normalized1.split(separator: " ").map(String.init))
        let words2 = Set(normalized2.split(separator: " ").map(String.init))
        
        let commonWords = words1.intersection(words2)
        
        return !commonWords.isEmpty ||
            normalized1.contains(normalized2) ||
            normalized2.contains(normalized1)
    }
    
    private func updateCartFromLayout(_ layout: [PlacedFurnitureWithMetadata]) {
        var newCart: [String: Int] = [:]
        var newTotal: Float = 0.0
        
        for item in layout {
            let category = item.metadata.category
            newCart[category, default: 0] += 1
            newTotal += item.metadata.price
        }
        
        DispatchQueue.main.async {
            self.furnitureCart = newCart
            self.totalPrice = newTotal
            print("💰 Cart updated: \(newCart.count) categories, $\(String(format: "%.2f", newTotal))")
        }
    }
    
    private func removeItemFromCart(category: String) {
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
    
    private func updateTotalPrice() {
        var total: Float = 0.0
        for item in furnitureWithMetadata {
            let category = item.metadata.category
            let count = Float(furnitureCart[category] ?? 0)
            total += item.metadata.price * count
        }
        totalPrice = total
    }
    
    // ============================================================================
    // PLACE FURNITURE IN SCENE
    // ============================================================================
    
    func placeFurnitureList(_ layout: [PlacedFurniture], in anchor: Entity, isPreview: Bool) {
        print("\n🏗️ Placing \(layout.count) furniture items in \(isPreview ? "preview" : "AR") mode...")
        
        totalFurnitureToLoad = layout.count
        furnitureLoaded = 0
        
        // Remove existing furniture
        anchor.children.forEach { child in
            if child.name.starts(with: "FURN_") {
                child.removeFromParent()
            }
        }
        
        // Place each item
        for (index, item) in layout.enumerated() {
            placeSingleFurnitureItem(
                item: item,
                in: anchor,
                index: index,
                isPreview: isPreview
            )
        }
        
        print("✅ All furniture placement initiated")
    }
    
    private func placeSingleFurnitureItem(
        item: PlacedFurniture,
        in anchor: Entity,
        index: Int,
        isPreview: Bool
    ) {
        // Find matching furniture data
        guard let furnitureData = availableFurniture.first(where: { matchCategory($0.category, item.category) }) else {
            print("   ⚠️ No furniture data for \(item.category)")
            return
        }
        
        guard let modelURLString = furnitureData.usdz3DUrl?.absoluteString else {
            print("   ❌ Invalid model URL for \(furnitureData.itemName)")
            return
        }
        
        Task {
            do {
                // Load the 3D model from URL (Assuming USDZCache exists in your project)
                let furnitureEntity = try await USDZCache.shared.loadEntity(from: modelURLString)
                
                // Normalize size
                let dimensions = furnitureData.dimensionsInMeters
                let (offset, scale) = normalizeFurniture(furnitureEntity, targetSize: dimensions)
                
                // Apply transformations
                furnitureEntity.scale = scale
                furnitureEntity.position = item.position + offset
                furnitureEntity.orientation = simd_quatf(angle: item.rotation * .pi / 180.0, axis: [0, 1, 0])
                furnitureEntity.name = "FURN_\(index)_\(furnitureData.itemName.replacingOccurrences(of: " ", with: "_"))"
                
                // Enable collision for interactions
                furnitureEntity.generateCollisionShapes(recursive: true)
                
                await MainActor.run {
                    anchor.addChild(furnitureEntity)
                    self.furnitureLoaded += 1
                    print("   ✅ Placed \(furnitureData.itemName) (\(self.furnitureLoaded)/\(self.totalFurnitureToLoad))")
                }
                
            } catch {
                print("   ❌ Failed to load \(furnitureData.itemName): \(error.localizedDescription)")
            }
        }
    }
    
    func placeSingleFurnitureInAR(
        item: PlacedFurniture,
        furnitureData: FurnitureItem,
        in anchor: Entity
    ) {
        guard let modelURLString = furnitureData.usdz3DUrl?.absoluteString else {
            print("❌ Invalid model URL for \(furnitureData.itemName)")
            return
        }
        
        Task {
            do {
                let furnitureEntity = try await USDZCache.shared.loadEntity(from: modelURLString)
                
                let dimensions = furnitureData.dimensionsInMeters
                let (offset, scale) = normalizeFurniture(furnitureEntity, targetSize: dimensions)
                
                furnitureEntity.scale = scale
                furnitureEntity.position = item.position + offset
                furnitureEntity.orientation = simd_quatf(angle: item.rotation * .pi / 180.0, axis: [0, 1, 0])
                
                let index = anchor.children.filter { $0.name.starts(with: "FURN_") }.count
                furnitureEntity.name = "FURN_\(index)_\(furnitureData.itemName.replacingOccurrences(of: " ", with: "_"))"
                
                furnitureEntity.generateCollisionShapes(recursive: true)
                
                await MainActor.run {
                    anchor.addChild(furnitureEntity)
                    print("✅ Added \(furnitureData.itemName) to AR scene")
                }
                
            } catch {
                print("❌ Failed to load \(furnitureData.itemName): \(error)")
            }
        }
    }
    
    // ============================================================================
    // API HELPERS
    // ============================================================================
    
    func getMacIP() -> String {
        return "172.20.10.11"  // Update this to your Mac's IP
    }
    
    @MainActor
    func callSearchAPI(macIP: String, prompt: String) async -> Data? {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = macIP
        comps.port = 8000
        comps.path = "/text/search_combined"
        
        guard let url = comps.url else {
            print("❌ Invalid search API URL")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = ["prompt": prompt]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to serialize request body")
            return nil
        }
        
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Search API response: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    return data
                } else {
                    print("❌ Search API error: \(httpResponse.statusCode)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("Error details: \(responseString)")
                    }
                }
            }
        } catch {
            print("❌ Search API network error: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    @MainActor
    func callGeminiAPI(prompt: String) async -> Data? {
        let apiKey = "AIzaSyClvAPSXDweflBx4HyHCD7StHop6i3xojY"
        
        let modelName = "gemini-2.5-flash"
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)") else {
                print("❌ Invalid Gemini API URL")
                return nil
            }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to serialize Gemini request")
            return nil
        }
        
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Gemini API response: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // Parse Gemini response to extract text
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let candidates = json["candidates"] as? [[String: Any]],
                       let firstCandidate = candidates.first,
                       let content = firstCandidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let firstPart = parts.first,
                       let text = firstPart["text"] as? String {
                        return text.data(using: .utf8)
                    }
                } else {
                    print("❌ Gemini API error: \(httpResponse.statusCode)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("Error details: \(responseString.prefix(500))")
                    }
                }
            }
        } catch {
            print("❌ Gemini API network error: \(error.localizedDescription)")
        }
        
        return nil
    }
}
