import ARKit
import Foundation
import SceneKit
import Core

public class VirtualObjectPresenter {

    private let appRouter: VirtualObjectRouterProtocol
    internal let type: VirtualObjectType

    public init(appRouter: VirtualObjectRouterProtocol, type: VirtualObjectType) {
        self.appRouter = appRouter
        self.type = type
    }

    private var modelCache: [String: SCNNode] = [:]

    func addVirtualObject(screenCenter: CGPoint?, sceneView: ARSCNView) {
        addVirtualObject(ofType: self.type, screenCenter: screenCenter, sceneView: sceneView)
    }
    
    // In VirtualObjectPresenter.swift (public)
    public func preloadVirtualObject(named modelName: String) {
        _ = loadVirtualObject(named: modelName) // reuse existing loader which caches templates
    }
    
    public func addVirtualObject(ofType objType: VirtualObjectType, screenCenter: CGPoint?, sceneView: ARSCNView) {
        guard
            let center = screenCenter,
            let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
            let transform = sceneView.session.raycast(query).first?.worldTransform
        else {
            if #available(macOS 10.15, iOS 13.0, *) {
                print("PRES: addVirtualObject(ofType:) -> no valid raycast at center")
            }
            return
        }

        // Load the model (this returns a cloned instance from the cached template)
        guard let objectNode = loadVirtualObject(named: objType.rawValue) else {
            if #available(macOS 10.15, iOS 13.0, *) {
                print("PRES: addVirtualObject(ofType:) -> failed to load model '\(objType.rawValue)'")
            }
            return
        }

        // Place model at the raycast transform
        let position = SCNVector3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        objectNode.position = position

        // Apply a sensible default scale — you may tune or compute this per-model elsewhere
        objectNode.scale = SCNVector3(0.01, 0.01, 0.01)

        // Ensure materials / lighting are set on this instance
        objectNode.enumerateChildNodes { (node, _) in
            node.castsShadow = true
            node.geometry?.firstMaterial?.lightingModel = .physicallyBased
        }

        // Create delete badge (billboard) and position it relative to the model's bounding box
        let badgeSize: CGFloat = 0.06 // meters
        let plane = SCNPlane(width: badgeSize, height: badgeSize)
        if let minusImage = UIImage(systemName: "minus.circle.fill") {
            plane.firstMaterial?.diffuse.contents = minusImage.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        } else {
            plane.firstMaterial?.diffuse.contents = UIColor.systemRed
        }
        plane.firstMaterial?.isDoubleSided = true
        plane.cornerRadius = badgeSize * 0.15

        let badgeNode = SCNNode(geometry: plane)
        badgeNode.name = "deleteBadge"
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        badgeNode.constraints = [billboard]

        // Use boundingBox to compute top Y; fall back to a small offset if bounding box is empty
        let (minVec, maxVec) = objectNode.boundingBox
        let modelHeight = max(0.02, CGFloat(maxVec.y - minVec.y))
        let topY: Float = (maxVec.y - minVec.y > 0.0001) ? maxVec.y : (objectNode.position.y + Float(modelHeight) * 0.5)
        badgeNode.position = SCNVector3(0, topY + Float(modelHeight) * 0.08 + 0.02, 0)

        badgeNode.castsShadow = false
        if let mat = badgeNode.geometry?.firstMaterial {
            mat.lightingModel = .constant
            mat.readsFromDepthBuffer = true
            mat.writesToDepthBuffer = true
        }
        badgeNode.renderingOrder = 2000

        // Attach badge to the object node (so it moves with model). Keep badge local-position.
        objectNode.addChildNode(badgeNode)

        // Add to scene root (we do NOT mutate the template cache)
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene.rootNode.castsShadow = true
        sceneView.scene.rootNode.addChildNode(objectNode)

        // Give the instance a stable name so you can find it later (do not overwrite modelCache)
        let instanceId = "\(objType.rawValue)-\(UUID().uuidString)"
        objectNode.name = instanceId

        if #available(macOS 10.15, iOS 13.0, *) {
            print("PRES: addVirtualObject(ofType:) -> added instance '\(instanceId)' for model '\(objType.rawValue)' at \(position)")
        }
    }
    
    // Return available types (so VC/palette can list them)
    public func availableObjectTypes() -> [VirtualObjectType] {
        return VirtualObjectType.allCases
    }
    
    // Remove node helper — UNDO any scene cleanup / cache if needed
    public func removeVirtualObject(node: SCNNode) {
        // find the top-most ancestor (the highest node in the chain)
        var top: SCNNode = node
        while let parent = top.parent {
            top = parent
        }

        // Remove from scene safely on main thread
        DispatchQueue.main.async {
            top.removeFromParentNode()

            // Remove any cached entry that points to this exact node instance
            let keysToRemove = self.modelCache.compactMap { (key, value) -> String? in
                return value === top ? key : nil
            }
            for k in keysToRemove {
                self.modelCache.removeValue(forKey: k)
            }
        }
    }



    private func loadVirtualObject(named modelName: String, type: FileType = .usdz) -> SCNNode? {
        // Normalize cache key: use modelName without extension (assumes rawValue passed in without extension)
        let cacheKey = modelName

        if let cachedNode = modelCache[cacheKey] {
            if #available(iOS 10.0, *) { print("PRES: loadVirtualObject -> returning clone from cache for '\(cacheKey)'") }
            return cachedNode.clone()
        }

        if #available(iOS 10.0, *) { print("PRES: loadVirtualObject -> loading '\(modelName)' from bundle (ext=\(type.fileExtension))") }

        guard
            let url = Bundle.module.url(forResource: modelName, withExtension: type.fileExtension),
            let scene = try? SCNScene(url: url)
        else {
            showErrorPopup(for: .loadObject)
            if #available(iOS 10.0, *) { print("PRES: loadVirtualObject -> failed to load '\(modelName)'") }
            return nil
        }

        // Use first child node as model root (safe fallback). Clone for caching to avoid sharing same instance.
        let modelNode = scene.rootNode.childNodes.first?.clone() ?? SCNNode()
        modelCache[cacheKey] = modelNode

        if #available(iOS 10.0, *) { print("PRES: loadVirtualObject -> loaded and cached template for '\(cacheKey)'") }
        return modelNode.clone()
    }



    func showErrorPopup(for type: VirtualObjectErrorType) {
        appRouter.showErrorPopup(for: type)
    }

}

private extension SCNVector3 {
    static func - (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        return SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        return SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }
}

