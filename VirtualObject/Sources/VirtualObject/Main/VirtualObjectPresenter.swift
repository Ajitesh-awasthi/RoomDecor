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
//        guard
//            let center = screenCenter,
//            let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
//            let transform = sceneView.session.raycast(query).first?.worldTransform,
//            let objectNode = loadVirtualObject(named: type.rawValue)
//        else { return }
//
//        // place model
//        let position = SCNVector3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
//        objectNode.position = position
//        objectNode.scale = SCNVector3(0.01, 0.01, 0.01)
//
//        objectNode.enumerateChildNodes { (node, _) in
//            node.castsShadow = true
//            node.geometry?.firstMaterial?.lightingModel = .physicallyBased
//        }
//
//        // --- ADD: create a small "delete" badge that always faces the camera ---
//        let badgeSize: CGFloat = 0.06 // meters — tweak if needed
//        let plane = SCNPlane(width: badgeSize, height: badgeSize)
//        let mat = SCNMaterial()
//        if let minusImage = UIImage(systemName: "minus.circle.fill") {
//            mat.diffuse.contents = minusImage.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
//        } else {
//            mat.diffuse.contents = UIColor.systemRed
//        }
//        mat.isDoubleSided = true
//        mat.lightingModel = .constant
//        plane.firstMaterial = mat
//        plane.cornerRadius = badgeSize * 0.15
//
//        let badgeNode = SCNNode(geometry: plane)
//        badgeNode.name = "deleteBadge" // identifier used in hit tests
//        let billboard = SCNBillboardConstraint()
//        billboard.freeAxes = .Y
//        badgeNode.constraints = [billboard]
//
//        // --- Use boundingBox tuple (Swift) to compute badge position ---
//        let (minVec, maxVec) = objectNode.boundingBox
//        let heightVec = maxVec - minVec
//        let topY: Float
//        if (heightVec.y > 0.0001) {
//            topY = maxVec.y
//        } else {
//            // fallback: if bounding box empty, place relative to node.position
//            topY = objectNode.position.y + 0.1
//        }
//        // place slightly above the top of the model (local coordinates)
//        let modelHeight = max(0.02, CGFloat(heightVec.y))
//        badgeNode.position = SCNVector3(0, topY + Float(modelHeight) * 0.08 + 0.02, 0)
//
//        // appearance tweaks
//        badgeNode.castsShadow = false
//        badgeNode.renderingOrder = 2_000
//
//        // attach badge to model node so it moves with it
//        objectNode.addChildNode(badgeNode)
//
//        // finally add the object to the scene
//        sceneView.autoenablesDefaultLighting = true
//        sceneView.automaticallyUpdatesLighting = true
//        sceneView.scene.rootNode.castsShadow = true
//        sceneView.scene.rootNode.addChildNode(objectNode)
//
//        // cache node keyed by a generated id (helpful if you need to remove via presenter)
//        let key = "\(type.rawValue)-\(UUID().uuidString)"
//        modelCache[key] = objectNode
//        objectNode.name = key
        addVirtualObject(ofType: self.type, screenCenter: screenCenter, sceneView: sceneView)
    }
    
    // Add to VirtualObjectPresenter
    public func addVirtualObject(ofType objType: VirtualObjectType, screenCenter: CGPoint?, sceneView: ARSCNView) {
        guard
            let center = screenCenter,
            let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
            let transform = sceneView.session.raycast(query).first?.worldTransform,
            let objectNode = loadVirtualObject(named: objType.rawValue)
        else { return }

        // place model
        let position = SCNVector3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        objectNode.position = position
        objectNode.scale = SCNVector3(0.01, 0.01, 0.01)

        objectNode.enumerateChildNodes { (node, _) in
            node.castsShadow = true
            node.geometry?.firstMaterial?.lightingModel = .physicallyBased
        }

        // create delete badge that faces camera
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

        // compute top of model using boundingBox
        let (minVec, maxVec) = objectNode.boundingBox
        let topY: Float
        if maxVec.y - minVec.y > 0.0001 {
            topY = maxVec.y
        } else {
            topY = objectNode.position.y + 0.1
        }
        let modelHeight = max(0.02, CGFloat(maxVec.y - minVec.y))
        badgeNode.position = SCNVector3(0, topY + Float(modelHeight) * 0.08 + 0.02, 0)

        badgeNode.castsShadow = false
        if let mat = badgeNode.geometry?.firstMaterial {
            mat.lightingModel = .constant
            mat.readsFromDepthBuffer = true
            mat.writesToDepthBuffer = true
        }
        badgeNode.renderingOrder = 2_000

        objectNode.addChildNode(badgeNode)

        // add to scene
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene.rootNode.castsShadow = true
        sceneView.scene.rootNode.addChildNode(objectNode)

        // cache instance and set unique name
        let key = "\(objType.rawValue)-\(UUID().uuidString)"
        modelCache[key] = objectNode
        objectNode.name = key
    }
    
    // Return available types (so VC/palette can list them)
    public func availableObjectTypes() -> [VirtualObjectType] {
        return VirtualObjectType.allCases
    }

    
//    func removeVirtualObject(node: SCNNode) {
//        // Remove from scene
//        node.removeFromParentNode()
//
//        // Remove from cache if present (search by identity)
//        if let key = modelCache.first(where: { $0.value === node })?.key {
//            modelCache.removeValue(forKey: key)
//        } else {
//            // If node was a clone or wrapped, try matching by name
//            if let name = node.name {
//                modelCache.removeValue(forKey: name)
//            }
//        }
//    }
    
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
        if let cachedNode = modelCache[modelName] {
            return cachedNode.clone() // Use clone to duplicate the node if needed
        }

        guard
            let url = Bundle.module.url(forResource: modelName, withExtension: type.fileExtension),
            let scene = try? SCNScene(url: url)
        else {
            showErrorPopup(for: .loadObject)
            return nil
        }

        let modelNode = scene.rootNode.childNodes.first
        modelCache[modelName] = modelNode // Cache the loaded model
        return modelNode?.clone() // Return a clone if you will add this to the scene multiple times
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

