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
    // private let originalName = "3d"
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
                        coordinator.generateDesignFromPrompt(prompt, from: self.scanURL) { layout in
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
                    onBackToScan: {  // ✅ ADD THIS
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
                        coordinator.generateDesignFromPrompt(prompt, from: self.scanURL) { newLayout in
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
                    onBackToScan: {  // ✅ ADD THIS
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
                        let updatedCart = newLayout.reduce(into: [String: Int]()) { counts, item in
                            counts[item.category, default: 0] += 1
                        }
                        coordinator.furnitureCart = updatedCart
                        coordinator.updateTotalPrice()
                        print("🛒 Cart re-synced from AR: \(updatedCart)")
                        self.appState = .previewing(
                            layout: newLayout,
                            theme: theme ?? predefinedThemes["modern"]!
                        )                    }
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
                .onAppear {  // ← ADD THIS
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
            
            // ✅ ADD THIS PARAMETER FOR BACK NAVIGATION
            var onBackToScan: (() -> Void)?  // ← NEW
            
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
                        if let anchor = content.entities.first(where: { $0.name == "RoomAnchor" }) {
                            var transform = Transform.identity
                            transform.scale = SIMD3<Float>(repeating: Float(self.zoomScale))
                            
                            let yaw = simd_quatf(angle: Float(self.yawAngle) * .pi / 180.0, axis: [0, 1, 0])
                            let pitch = simd_quatf(angle: Float(self.pitchAngle) * .pi / 180.0, axis: [1, 0, 0])
                            transform.rotation = yaw * pitch
                            
                            anchor.transform = transform
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                self.yawAngle += value.translation.width * 0.1
                                let newPitch = self.pitchAngle - value.translation.height * 0.1
                                self.pitchAngle = max(-89.0, min(89.0, newPitch))
                            }
                    )
                    
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let gestureValue = Double(value)
                                guard !gestureValue.isNaN, gestureValue > 0 else { return }
                                self.zoomScale = max(0.3, min(3.0, self.startScale * gestureValue))
                            }
                            .onEnded { value in
                                self.startScale = self.zoomScale
                            }
                    )
                    .id(refreshID)
                    .onChange(of: generatedLayout?.count) { _ in
                        refreshID = UUID()
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
                        cart: coordinator.furnitureCart,
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
            let cart: [String: Int]
            var onDismiss: () -> Void
            
            private var sortedKeys: [String] {
                cart.keys.sorted()
            }
            
            var body: some View {
                NavigationView {
                    List {
                        Section(header: Text("Items in Your Plan")) {
                            if cart.isEmpty {
                                Text("Your cart is empty.")
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(sortedKeys, id: \.self) { category in
                                    HStack(spacing: 15) {
                                        Image(systemName: iconFor(category: category))
                                            .font(.title3)
                                            .frame(width: 30)
                                            .foregroundColor(.blue)
                                        
                                        Text(category)
                                            .font(.headline)
                                        
                                        Spacer()
                                        
                                        Text("x\(cart[category] ?? 0)")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                        
                                        Text(String(format: "$%.2f", furnitureMetadata[category]?.price ?? 0.0))
                                            .font(.caption)
                                            .frame(width: 70, alignment: .trailing)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        
                        if !cart.isEmpty {
                            Section(header: Text("Summary")) {
                                HStack {
                                    Image(systemName: "sum")
                                        .font(.headline)
                                    Text("Total Items")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(cart.values.reduce(0, +))")
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
            
            private func iconFor(category: String) -> String {
                switch category {
                case "Sofa": return "sofa.fill"
                case "Table": return "table.furniture.fill"
                case "Lamp": return "lightbulb.fill"
                case "Study Desk": return "macbook"
                case "Office Chair": return "chair.fill"
                case "Bookshelf": return "books.vertical.fill"
                case "Bed": return "bed.double.fill"
                case "Painting": return "photo.fill"
                case "Pot": return "leaf.fill"
                case "Wall_Clock": return "clock.fill"
                case "Wardrobe": return "cabinet.fill"
                case "Dressing_Table": return "mirror.fill"
                default: return "square.grid.2x2.fill"
                }
            }
        }
        
        // ============================================================================
        // AR EDITING VIEW
        // ============================================================================
        struct AREditingView: View {
            let scanURL: URL // <-- 1. Add this
            @ObservedObject var coordinator: ARCoordinator
            var initialLayout: [PlacedFurniture]
            var roomTheme: RoomTheme?
            @Binding var sceneLoadError: String?
            var onGoBackToPreview: ([PlacedFurniture]) -> Void
            
            @State private var showCartSheet: Bool = false
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
                        Spacer()
                        
                        if showBoundaryWarning {
                            Text(boundaryWarningMessage)
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.red.opacity(0.9))
                                .cornerRadius(10)
                                .padding()
                                .transition(.move(edge: .bottom))
                                .animation(.easeInOut, value: showBoundaryWarning)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                        showBoundaryWarning = false
                                    }
                                }
                        }
                        
                        HStack(alignment: .bottom) {
                            Button(action: {
                                let currentLayout = coordinator.getCurrentLayout()
                                onGoBackToPreview(currentLayout)
                            }) {
                                Label("Back to Preview", systemImage: "chevron.backward")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.black.opacity(0.6))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            
                            Spacer()
                            
                            VStack(spacing: 20) {
                                Menu {
                                    let furnitureNames = Array(furnitureAssets.keys.sorted())
                                    ForEach(furnitureNames, id: \.self) { name in
                                        Button(action: {
                                            selectedFurniture = name
                                            print("Palette: Selected \(name)")
                                        }) {
                                            Label(name, systemImage: iconFor(category: name))
                                        }
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title)
                                        .frame(width: 50, height: 50)
                                        .background(Color.blue.opacity(0.9))
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    self.showCartSheet = true
                                }) {
                                    Image(systemName: "cart")
                                        .font(.title2)
                                        .frame(width: 50, height: 50)
                                        .background(Color.black.opacity(0.6))
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
                            }
                        }
                        .padding()
                    }
                    
                    // Delete confirmation dialog
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
                                        coordinator.deleteFurniture(furniture)
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
                        cart: coordinator.furnitureCart,
                        onDismiss: { self.showCartSheet = false }
                    )
                }
                .onAppear {
                    coordinator.selectedFurniture = self.selectedFurniture
                }
                .onChange(of: selectedFurniture) { newValue in
                    coordinator.selectedFurniture = newValue
                }
            }
            
            private func iconFor(category: String) -> String {
                switch category {
                case "Sofa": return "sofa.fill"
                case "Table": return "table.furniture.fill"
                case "Lamp": return "lightbulb.fill"
                case "Study Desk": return "macbook"
                case "Office Chair": return "chair.fill"
                case "Bookshelf": return "books.vertical.fill"
                case "Bed": return "bed.double.fill"
                case "Painting": return "photo.fill"
                case "Pot": return "leaf.fill"
                case "Wall_Clock": return "clock.fill"
                case "Wardrobe": return "cabinet.fill"
                case "Dressing_Table": return "mirror.fill"
                default: return "square.grid.2x2.fill"
                }
            }
        }
        
        // ============================================================================
        // AR VIEW CONTAINER
        // ============================================================================
        // ============================================================================
        // AR VIEW CONTAINER (CORRECTED VERSION)
        // ============================================================================
        struct ARViewContainer: UIViewRepresentable {
            
            // --- Properties belong here, at the struct level ---
            let scanURL: URL
            @ObservedObject var coordinator: ARCoordinator
            var initialLayout: [PlacedFurniture]
            var roomTheme: RoomTheme?
            @Binding var showBoundaryWarning: Bool
            @Binding var boundaryWarningMessage: String
            @Binding var showDeleteConfirmation: Bool
            @Binding var furnitureToDelete: Entity?
            
            // --- This is the first function ---
            func makeUIView(context: Context) -> ARView {
                let arView = ARView(frame: .zero)
                coordinator.arView = arView
                coordinator.showBoundaryWarningBinding = $showBoundaryWarning
                coordinator.boundaryWarningMessageBinding = $boundaryWarningMessage
                coordinator.showDeleteConfirmationBinding = $showDeleteConfirmation
                coordinator.furnitureToDeleteBinding = $furnitureToDelete
                
                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal]
                arView.session.run(config)
                
                let coachingOverlay = ARCoachingOverlayView()
                coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                coachingOverlay.session = arView.session
                coachingOverlay.goal = .horizontalPlane
                arView.addSubview(coachingOverlay)
                
                let tapGesture = UITapGestureRecognizer(target: coordinator, action: #selector(ARCoordinator.handleTap))
                arView.addGestureRecognizer(tapGesture)
                
                let longPressGesture = UILongPressGestureRecognizer(target: coordinator, action: #selector(ARCoordinator.handleLongPress))
                longPressGesture.minimumPressDuration = 0.5
                arView.addGestureRecognizer(longPressGesture)
                
                // --- This block now correctly uses self.scanURL ---
                do {
                    let roomEntity = try Entity.load(contentsOf: self.scanURL) // <-- USES THE PROPERTY
                    let analysis = processLoadedRoom(entity: roomEntity)
                    coordinator.roomBounds = analysis.overallBounds.toMDLAxisAlignedBoundingBox()
                    coordinator.structuralElements = analysis.elements
                    coordinator.doorLocations = extractDoorLocations(from: analysis.elements)
                    
                    print("✅ Room bounds and \(analysis.elements.count) structural elements loaded.")
                    print("🚪 Found \(coordinator.doorLocations.count) doors")
                    
                    if let theme = roomTheme {
                        applyThemeToRoom(roomEntity: roomEntity, theme: theme)
                    }
                    
                    let roomAnchor = AnchorEntity()
                    roomAnchor.addChild(roomEntity)
                    arView.scene.addAnchor(roomAnchor)
                    roomEntity.addChild(coordinator.furnitureAnchor)
                    coordinator.placeFurnitureList(initialLayout, in: coordinator.furnitureAnchor, isPreview: false) // <-- ADD THIS
                } catch {
                    coordinator.sceneLoadError = "Room failed to load: \(error.localizedDescription)"
                }
                // --- END OF FIXED BLOCK ---
                
                return arView
            }
            
            // --- This is the second function ---
            func updateUIView(_ uiView: ARView, context: Context) {}
            
            // --- This is the third function ---
            func makeCoordinator() -> ARCoordinator {
                coordinator
            }
        }
    }
