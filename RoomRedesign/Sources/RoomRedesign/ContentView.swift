import SwiftUI
import RealityKit
import ARKit
import UIKit

// ============================================================================
// MAIN APP STATE
// ============================================================================
enum AppState {
    case prompting
    case previewing(layout: [PlacedFurniture], theme: RoomTheme)
    case editingInAR(layout: [PlacedFurniture], theme: RoomTheme?)
}

// ============================================================================
// MAIN CONTENT VIEW
// ============================================================================
public struct ContentView: View {
    let scanURL: URL
    @State private var sceneLoadError: String? = nil
    @State private var isLoading: Bool = false
    @StateObject private var coordinator = ARCoordinator()
    @State private var appState: AppState = .prompting
    @Environment(\.dismiss) var dismiss
    
    public init(scanURL: URL) {
        self.scanURL = scanURL
    }
    
    public var body: some View {
        ZStack {
            switch appState {
            case .prompting:
                PreviewView(
                    scanURL: self.scanURL,
                    coordinator: coordinator,
                    showARButton: false,
                    generatedLayout: nil,
                    roomTheme: nil,
                    onGenerate: { prompt in
                        self.isLoading = true
                        coordinator.generateDesignWithSearch(prompt, from: self.scanURL) { layout in
                            self.isLoading = false
                            if let layout = layout {
                                let theme = detectThemeFromPrompt(prompt)
                                self.appState = .previewing(layout: layout, theme: theme)
                            } else {
                                self.sceneLoadError = "AI design failed. Please try again."
                            }
                        }
                    },
                    onGoToAR: { _, _ in },
                    onBackToScan: {
                        dismiss()
                    }
                )
                
            case .previewing(let layout, let theme):
                PreviewView(
                    scanURL: self.scanURL,
                    coordinator: coordinator,
                    showARButton: true,
                    generatedLayout: layout,
                    roomTheme: theme,
                    onGenerate: { prompt in
                        self.isLoading = true
                        coordinator.generateDesignWithSearch(prompt, from: self.scanURL) { newLayout in
                            self.isLoading = false
                            if let newLayout = newLayout {
                                let newTheme = detectThemeFromPrompt(prompt)
                                self.appState = .previewing(layout: newLayout, theme: newTheme)
                            } else {
                                self.sceneLoadError = "AI design failed. Please try again."
                            }
                        }
                    },
                    onGoToAR: { generatedLayout, currentTheme in
                        self.appState = .editingInAR(
                            layout: generatedLayout,
                            theme: currentTheme ?? predefinedThemes["modern"]!
                        )
                    },
                    onBackToScan: {
                        dismiss()
                    }
                )
                
            case .editingInAR(let layout, let theme):
                AREditingView(
                    scanURL: self.scanURL,
                    coordinator: coordinator,
                    initialLayout: layout,
                    roomTheme: theme,
                    sceneLoadError: $sceneLoadError,
                    onGoBackToPreview: { newLayout in
                        coordinator.syncLayoutFromAR(newLayout)
                        print("🛒 Cart re-synced from AR: \(coordinator.furnitureCart)")
                        
                        let currentTheme = theme ?? predefinedThemes["modern"]!
                        self.appState = .prompting
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.appState = .previewing(layout: newLayout, theme: currentTheme)
                        }
                    }
                )
                .edgesIgnoringSafeArea(.all)
            }
            
            if isLoading {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2)
            }
            
            if let err = sceneLoadError {
                VStack {
                    Text(err)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                        .padding()
                    Spacer()
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        sceneLoadError = nil
                    }
                }
                .onTapGesture {
                    sceneLoadError = nil
                }
                .onAppear {
                    coordinator.loadRoomBounds(from: scanURL)
                }
            }
        }
    }
}

// ============================================================================
// PREVIEW VIEW
// ============================================================================
struct PreviewView: View {
    let scanURL: URL
    @ObservedObject var coordinator: ARCoordinator
    var showARButton: Bool
    var generatedLayout: [PlacedFurniture]?
    var roomTheme: RoomTheme?
    var onGenerate: (String) -> Void
    var onGoToAR: ([PlacedFurniture], RoomTheme?) -> Void
    var onBackToScan: (() -> Void)?
    
    var furnitureCount: Int {
        generatedLayout?.count ?? 0
    }
    
    @State private var userPrompt: String = ""
    @State private var showCartSheet: Bool = false
    @State private var yawAngle: Double = 0.0
    @State private var pitchAngle: Double = -15.0
    @State private var zoomScale: Double = 1.0
    @State private var startScale: Double = 1.0
    @State private var refreshID = UUID()
    
    var body: some View {
        ZStack {
            RealityView { content in
                guard let roomEntity = try? Entity.load(contentsOf: scanURL) else { return }
                
                let _ = processLoadedRoom(entity: roomEntity)
                
                if let theme = roomTheme {
                    applyThemeToRoom(roomEntity: roomEntity, theme: theme)
                }
                
                let anchor = AnchorEntity(.world(transform: matrix_identity_float4x4))
                anchor.name = "RoomAnchor"
                anchor.addChild(roomEntity)
                
                if let layout = generatedLayout {
                    let furnitureAnchor = Entity()
                    furnitureAnchor.name = "FurnitureAnchor"
                    roomEntity.addChild(furnitureAnchor)
                    coordinator.placeFurnitureList(layout, in: furnitureAnchor, isPreview: true)
                }
                
                content.add(anchor)
                
                let sun = DirectionalLight()
                sun.light.intensity = 15000
                sun.transform.translation = [0, 5, 5]
                sun.look(at: .zero, from: sun.transform.translation, relativeTo: nil)
                content.add(sun)
                
                let camera = PerspectiveCamera()
                camera.transform.translation = [0, 4, 12]
                camera.look(at: .zero, from: camera.transform.translation, relativeTo: nil)
                content.add(camera)
            } update: { content in
                guard let anchor = content.entities.first(where: { $0.name == "RoomAnchor" }) else { return }
                
                let rotation = simd_quatf(angle: Float(yawAngle) * .pi / 180.0, axis: [0, 1, 0]) *
                               simd_quatf(angle: Float(pitchAngle) * .pi / 180.0, axis: [1, 0, 0])
                
                anchor.orientation = rotation
                anchor.scale = [Float(zoomScale), Float(zoomScale), Float(zoomScale)]
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.translation
                        self.yawAngle += Double(delta.width) * 0.2
                        self.pitchAngle = max(-45, min(15, self.pitchAngle + Double(delta.height) * 0.2))
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        self.zoomScale = max(0.5, min(3.0, self.startScale * value))
                    }
                    .onEnded { value in
                        self.startScale = self.zoomScale
                    }
            )
            .id(refreshID)
            .onChange(of: furnitureCount) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    refreshID = UUID()
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                if let backAction = onBackToScan {
                    HStack {
                        Button(action: backAction) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back to Scan")
                            }
                            .font(.headline)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding()
                        Spacer()
                    }
                }
                
                Spacer()
                
                if showARButton {
                    Text(String(format: "Est. Total Price: $%.2f", coordinator.totalPrice))
                        .font(.headline)
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom, 5)
                    
                    HStack(spacing: 15) {
                        Button(action: {
                            self.showCartSheet = true
                        }) {
                            Image(systemName: "cart")
                                .font(.headline)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .overlay(
                                    ZStack {
                                        let totalItems = coordinator.furnitureCart.values.reduce(0, +)
                                        if totalItems > 0 {
                                            Circle().fill(Color.red).frame(width: 24, height: 24)
                                            Text("\(totalItems)").font(.caption).foregroundColor(.white).bold()
                                        }
                                    }
                                    .offset(x: 15, y: -15)
                                    .opacity(coordinator.furnitureCart.isEmpty ? 0 : 1)
                                )
                        }
                        
                        Button(action: {
                            onGoToAR(generatedLayout ?? [], roomTheme)
                        }) {
                            Label("Go to AR to Edit", systemImage: "arkit")
                                .font(.headline)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.bottom, 10)
                }
                
                HStack {
                    TextField("e.g., Make this a study room...", text: $userPrompt)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                    
                    Button(action: {
                        onGenerate(userPrompt)
                        userPrompt = ""
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(userPrompt.isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .sheet(isPresented: $showCartSheet) {
            CartView(
                coordinator: coordinator,
                onDismiss: { self.showCartSheet = false }
            )
        }
    }
}

// ============================================================================
// CART VIEW
// ============================================================================
struct CartView: View {
    @ObservedObject var coordinator: ARCoordinator
    var onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Items in Your Plan")) {
                    if coordinator.furnitureWithMetadata.isEmpty {
                        Text("Your cart is empty.")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ForEach(coordinator.furnitureWithMetadata) { item in
                            HStack(spacing: 15) {
                                AsyncImage(url: URL(string: item.metadata.imageLink2D)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(ProgressView())
                                }
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.metadata.itemName)
                                        .font(.headline)
                                    
                                    Text(item.metadata.category)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundColor(.yellow)
                                        Text(String(format: "%.1f", item.metadata.rating))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Text(String(format: "$%.2f", item.metadata.price))
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                if !coordinator.furnitureWithMetadata.isEmpty {
                    Section(header: Text("Summary")) {
                        HStack {
                            Image(systemName: "sum")
                                .font(.headline)
                            Text("Total Items")
                                .font(.headline)
                            Spacer()
                            Text("\(coordinator.furnitureWithMetadata.count)")
                                .font(.headline)
                                .bold()
                        }
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.headline)
                                .foregroundColor(.green)
                            Text("Estimated Total Price")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "$%.2f", coordinator.totalPrice))
                                .font(.headline)
                                .bold()
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Furniture List")
            .navigationBarItems(trailing:
                Button("Done") {
                    onDismiss()
                }
            )
        }
    }
}

// ============================================================================
// AR EDITING VIEW
// ============================================================================
struct AREditingView: View {
    let scanURL: URL
    @ObservedObject var coordinator: ARCoordinator
    var initialLayout: [PlacedFurniture]
    var roomTheme: RoomTheme?
    @Binding var sceneLoadError: String?
    var onGoBackToPreview: ([PlacedFurniture]) -> Void
    
    @State private var showCartSheet: Bool = false
    @State private var showFurnitureSelector: Bool = false
    @State private var selectedFurniture: String? = nil
    @State private var showBoundaryWarning: Bool = false
    @State private var boundaryWarningMessage: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var furnitureToDelete: Entity? = nil
    
    var body: some View {
        ZStack {
            ARViewContainer(
                scanURL: self.scanURL,
                coordinator: coordinator,
                initialLayout: initialLayout,
                roomTheme: roomTheme,
                showBoundaryWarning: $showBoundaryWarning,
                boundaryWarningMessage: $boundaryWarningMessage,
                showDeleteConfirmation: $showDeleteConfirmation,
                furnitureToDelete: $furnitureToDelete
            )
            
            VStack {
                HStack {
                    Button(action: {
                        let currentLayout = extractCurrentLayout(from: coordinator.furnitureAnchor)
                        coordinator.syncLayoutFromAR(currentLayout)
                        onGoBackToPreview(currentLayout)
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back to Preview")
                        }
                        .font(.headline)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
                
                HStack(spacing: 15) {
                    Button(action: {
                        self.showFurnitureSelector = true
                    }) {
                        VStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                            Text("Add")
                                .font(.caption)
                        }
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        self.showCartSheet = true
                    }) {
                        ZStack {
                            VStack {
                                Image(systemName: "cart.fill")
                                    .font(.title)
                                Text("Cart")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            
                            let totalItems = coordinator.furnitureCart.values.reduce(0, +)
                            if totalItems > 0 {
                                Text("\(totalItems)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 25, y: -20)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            
            if showBoundaryWarning {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 15) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                    
                    Text(boundaryWarningMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button(action: {
                        showBoundaryWarning = false
                    }) {
                        Text("OK")
                            .font(.headline)
                            .padding()
                            .frame(width: 120)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(30)
                .background(Color.black.opacity(0.9))
                .cornerRadius(20)
            }
            
            if showDeleteConfirmation {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        showDeleteConfirmation = false
                        furnitureToDelete = nil
                    }
                
                VStack(spacing: 20) {
                    Text("Remove Item?")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 20) {
                        Button(action: {
                            showDeleteConfirmation = false
                            furnitureToDelete = nil
                        }) {
                            Text("Cancel")
                                .font(.headline)
                                .padding()
                                .frame(width: 120)
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        
                        Button(action: {
                            if let furniture = furnitureToDelete {
                                let components = furniture.name.split(separator: "_")
                                if components.count >= 3 {
                                    let furnitureName = components[2...].joined(separator: "_").replacingOccurrences(of: "_", with: " ")
                                    
                                    if let matchingItem = coordinator.availableFurniture.first(where: { item in
                                        coordinator.matchCategory(item.itemName, furnitureName)
                                    }) {
                                        coordinator.furnitureCart[matchingItem.itemName, default: 1] -= 1
                                        if coordinator.furnitureCart[matchingItem.itemName]! <= 0 {
                                            coordinator.furnitureCart.removeValue(forKey: matchingItem.itemName)
                                        }
                                        coordinator.totalPrice -= matchingItem.price
                                        print("🛒 Removed \(matchingItem.itemName) from cart")
                                    }
                                }
                                
                                furniture.removeFromParent()
                            }
                            showDeleteConfirmation = false
                            furnitureToDelete = nil
                        }) {
                            Text("Remove")
                                .font(.headline)
                                .padding()
                                .frame(width: 120)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(30)
                .background(Color.black.opacity(0.9))
                .cornerRadius(20)
            }
        }
        .sheet(isPresented: $showCartSheet) {
            CartView(
                coordinator: coordinator,
                onDismiss: { self.showCartSheet = false }
            )
        }
        .sheet(isPresented: $showFurnitureSelector) {
            FurnitureSelectorView(
                coordinator: coordinator,
                onDismiss: { self.showFurnitureSelector = false }
            )
        }
    }
    
    private func extractCurrentLayout(from anchor: Entity) -> [PlacedFurniture] {
        var layout: [PlacedFurniture] = []
        
        for child in anchor.children where child.name.starts(with: "FURN_") {
            let components = child.name.split(separator: "_")
            if components.count >= 3 {
                let categoryParts = Array(components.dropFirst(2))
                let category = categoryParts.joined(separator: "_").replacingOccurrences(of: "_", with: " ")
                
                let quat = child.transform.rotation
                let rotation = atan2(2.0 * (quat.vector.w * quat.vector.y + quat.vector.x * quat.vector.z),
                                     1.0 - 2.0 * (quat.vector.y * quat.vector.y + quat.vector.z * quat.vector.z)) * 180.0 / .pi
                
                layout.append(PlacedFurniture(
                    position: child.position,
                    rotation: rotation,
                    category: category
                ))
                
                print("📦 Extracted: \(category) at position \(child.position)")
            }
        }
        
        print("✅ Extracted \(layout.count) furniture items from AR")
        return layout
    }
}

// ============================================================================
// FURNITURE SELECTOR VIEW
// ============================================================================
struct FurnitureSelectorView: View {
    @ObservedObject var coordinator: ARCoordinator
    var onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                if coordinator.availableFurniture.isEmpty {
                    Text("No furniture available. Generate a design first.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(coordinator.availableFurniture) { item in
                        Button(action: {
                            addFurnitureToScene(item)
                            onDismiss()
                        }) {
                            HStack(spacing: 15) {
                                AsyncImage(url: URL(string: item.imageLink2D)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(ProgressView())
                                }
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.itemName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(item.category)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(String(format: "$%.2f", item.price))
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                        .bold()
                                }
                                
                                Spacer()
                                
                                Image(systemName: "plus.circle")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Add Furniture")
            .navigationBarItems(trailing:
                Button("Cancel") {
                    onDismiss()
                }
            )
        }
    }
    
    private func addFurnitureToScene(_ item: FurnitureItem) {
        print("➕ Adding \(item.itemName) to scene...")
        
        guard let floorElement = coordinator.structuralElements.first(where: { $0.type == "floor" }),
              let polygonData = floorElement.polygon else {
            print("❌ No floor data available")
            return
        }
        
        let polygon = polygonData.map { SIMD2<Float>($0[0], $0[1]) }
        let center = getPolygonCenter(polygon: polygon)
        let floorHeight = (floorElement.minBounds[1] + floorElement.maxBounds[1]) / 2.0
        
        let newPlacement = PlacedFurniture(
            position: SIMD3<Float>(center.x, floorHeight + 0.01, center.y),
            rotation: 0.0,
            category: item.category
        )
        
        coordinator.placeSingleFurnitureInAR(
            item: newPlacement,
            furnitureData: item,
            in: coordinator.furnitureAnchor
        )
        
        coordinator.furnitureCart[item.itemName, default: 0] += 1
        coordinator.totalPrice += item.price
        
        print("✅ Added \(item.itemName) to scene and cart")
    }
}

// ============================================================================
// AR VIEW CONTAINER
// ============================================================================
struct ARViewContainer: UIViewRepresentable {
    let scanURL: URL
    @ObservedObject var coordinator: ARCoordinator
    var initialLayout: [PlacedFurniture]
    var roomTheme: RoomTheme?
    @Binding var showBoundaryWarning: Bool
    @Binding var boundaryWarningMessage: String
    @Binding var showDeleteConfirmation: Bool
    @Binding var furnitureToDelete: Entity?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        coordinator.arView = arView
        coordinator.showBoundaryWarningBinding = $showBoundaryWarning
        coordinator.boundaryWarningMessageBinding = $boundaryWarningMessage
        coordinator.showDeleteConfirmationBinding = $showDeleteConfirmation
        coordinator.furnitureToDeleteBinding = $furnitureToDelete
        coordinator.setupARGestures(for: arView)
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        arView.addSubview(coachingOverlay)
        
        do {
            let roomEntity = try Entity.load(contentsOf: self.scanURL)
            let analysis = processLoadedRoom(entity: roomEntity)
            coordinator.roomBounds = analysis.overallBounds.toMDLAxisAlignedBoundingBox()
            coordinator.structuralElements = analysis.elements
            
            print("✅ Room bounds and \(analysis.elements.count) structural elements loaded.")
            
            if let theme = roomTheme {
                applyThemeToRoom(roomEntity: roomEntity, theme: theme)
            }
            
            let roomAnchor = AnchorEntity()
            roomAnchor.addChild(roomEntity)
            arView.scene.addAnchor(roomAnchor)
            roomEntity.addChild(coordinator.furnitureAnchor)
            coordinator.placeFurnitureList(initialLayout, in: coordinator.furnitureAnchor, isPreview: false)
        } catch {
            coordinator.sceneLoadError = "Room failed to load: \(error.localizedDescription)"
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    func makeCoordinator() -> ARCoordinator {
        coordinator
    }
}
