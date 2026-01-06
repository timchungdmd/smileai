import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

struct SmileTemplateParams {
    var posX: Float; var posY: Float; var posZ: Float
    var scale: Float; var curve: Float; var length: Float; var ratio: Float
}

struct DesignSceneWrapper: NSViewRepresentable {
    let scanURL: URL
    let mode: DesignMode
    
    var showSmileTemplate: Bool
    var smileParams: SmileTemplateParams
    
    // Interactive State
    var toothStates: [String: ToothState]
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    
    // Landmarks Support
    var landmarks: [LandmarkType: SCNVector3]
    var activeLandmarkType: LandmarkType?
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    
    var showGrid: Bool
    var onModelLoaded: ((_ bounds: (min: SCNVector3, max: SCNVector3)) -> Void)?
    
    func makeNSView(context: Context) -> EditorView {
        let view = EditorView()
        view.defaultCameraController.interactionMode = .orbitArcball
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.automaticTarget = true
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        view.scene = SCNScene()
        return view
    }
    
    func updateNSView(_ view: EditorView, context: Context) {
        view.currentMode = mode
        view.onToothSelected = onToothSelected
        view.onToothTransformChange = onToothTransformChange
        view.currentToothStates = toothStates
        view.activeLandmarkType = activeLandmarkType
        view.onLandmarkPicked = onLandmarkPicked
        
        guard let root = view.scene?.rootNode else { return }
        
        // Load Model
        if root.childNode(withName: "PATIENT_MODEL", recursively: true) == nil {
            if let scene = try? SCNScene(url: scanURL, options: nil),
               let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                
                let node = geoNode.clone()
                node.name = "PATIENT_MODEL"
                
                if let geo = node.geometry {
                    let (min, max) = geo.boundingBox
                    let cx = (min.x + max.x) / 2
                    let cy = (min.y + max.y) / 2
                    let cz = (min.z + max.z) / 2
                    node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
                }
                node.position = SCNVector3Zero
                
                // Material Setup
                node.geometry?.materials.forEach { mat in
                    mat.lightingModel = .lambert
                    mat.isDoubleSided = true
                    mat.specular.contents = NSColor.black
                    if mat.diffuse.contents == nil {
                        mat.diffuse.contents = NSColor(calibratedRed: 0.9, green: 0.85, blue: 0.8, alpha: 1.0)
                    }
                }
                
                root.addChildNode(node)
                
                DispatchQueue.main.async {
                    self.onModelLoaded?((min: node.boundingBox.min, max: node.boundingBox.max))
                    view.defaultCameraController.target = SCNVector3Zero
                    view.defaultCameraController.frameNodes([node])
                }
            }
        }
        
        updateSmileTemplate(root: root)
        updateLandmarkVisuals(root: root)
        updateGrid(root: root)
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findFirstGeometryNode(in: child) { return found }
        }
        return nil
    }
    
    // MARK: - Landmarks
    private func updateLandmarkVisuals(root: SCNNode) {
        let containerName = "LANDMARKS_CONTAINER"
        root.childNode(withName: containerName, recursively: false)?.removeFromParentNode()
        let container = SCNNode()
        container.name = containerName
        root.addChildNode(container)
        
        for (type, pos) in landmarks {
            let sphere = SCNSphere(radius: 0.002)
            let color: NSColor = (type == .midline) ? .green : (type == .lipLine ? .red : .blue)
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            let node = SCNNode(geometry: sphere)
            node.position = pos
            container.addChildNode(node)
        }
    }
    
    // MARK: - Smile Template Logic (FIXED TYPES)
    private func updateSmileTemplate(root: SCNNode) {
        let name = "SMILE_TEMPLATE"
        var templateNode = root.childNode(withName: name, recursively: false)
        
        if showSmileTemplate {
            if templateNode == nil {
                templateNode = createProceduralArch()
                templateNode?.name = name
                root.addChildNode(templateNode!)
            }
            
            var basePos = SCNVector3Zero
            var baseScale: Float = 1.0
            
            if let lCanine = landmarks[.leftCanine], let rCanine = landmarks[.rightCanine] {
                basePos = SCNVector3((lCanine.x + rCanine.x)/2, (lCanine.y + rCanine.y)/2, (lCanine.z + rCanine.z)/2)
                if let mid = landmarks[.midline] { basePos.x = mid.x }
                if let lip = landmarks[.lipLine] { basePos.y = lip.y + 0.002 }
                
                // Calculate distance using Float/CGFloat agnostic math
                let dx = rCanine.x - lCanine.x
                let dy = rCanine.y - lCanine.y
                let dz = rCanine.z - lCanine.z
                // Convert to Double for sqrt then back to Float
                let width = Float(sqrt(Double(dx*dx + dy*dy + dz*dz)))
                baseScale = width * 15.0
            }
            
            let finalScale = CGFloat(baseScale) * CGFloat(smileParams.scale)
            templateNode?.scale = SCNVector3(finalScale, finalScale, finalScale)
            
            // Explicit Float casting for position
            let px = Float(basePos.x) + smileParams.posX * 0.05
            let py = Float(basePos.y) + smileParams.posY * 0.05
            let pz = Float(basePos.z) + smileParams.posZ * 0.05
            templateNode?.position = SCNVector3(CGFloat(px), CGFloat(py), CGFloat(pz))
            
            templateNode?.childNodes.forEach { tooth in
                guard let toothName = tooth.name else { return }
                
                // 1. Get Base X as Float
                let xVal = Float(tooth.position.x)
                
                // 2. Calculate Curve Z as Float
                let curveZ = pow(xVal * 5.0, 2) * smileParams.curve * 0.5
                
                // 3. Get State Offsets (SIMD3<Float>)
                let state = toothStates[toothName] ?? ToothState()
                
                // 4. Calculate final positions as Float (FIXED: Broken up expressions)
                let newY = 0.0 + state.positionOffset.y * 0.01
                let newX = xVal + state.positionOffset.x * 0.01
                let newZ = curveZ + state.positionOffset.z * 0.01
                
                // 5. Assign using CGFloat cast (SCNVector3 requirement on macOS)
                tooth.position.y = CGFloat(newY)
                tooth.position.x = CGFloat(newX)
                tooth.position.z = CGFloat(newZ)
                
                tooth.eulerAngles = SCNVector3(0, 0, CGFloat(state.rotation.z))
                tooth.scale = SCNVector3(CGFloat(smileParams.ratio) * CGFloat(state.scale), CGFloat(smileParams.length) * CGFloat(state.scale), 1.0)
                
                if tooth.geometry?.firstMaterial?.emission.contents as? NSColor != NSColor.blue {
                    tooth.geometry?.firstMaterial?.emission.contents = NSColor.black
                }
            }
        } else {
            templateNode?.removeFromParentNode()
        }
    }
    
    private func createProceduralArch() -> SCNNode {
        let root = SCNNode()
        let baseW: CGFloat = 0.0085
        let definitions: [(id: Int, wRatio: CGFloat, hRatio: CGFloat)] = [(1, 1.0, 1.0), (2, 0.75, 0.85), (3, 0.85, 0.95)]
        var xCursor: CGFloat = baseW / 2.0
        for def in definitions {
            let w = baseW * def.wRatio; let h = baseW * 1.2 * def.hRatio
            let rNode = createToothGeo(width: w, height: h); rNode.position = SCNVector3(xCursor, 0, 0); rNode.name = "T_\(def.id)_R"; root.addChildNode(rNode)
            let lNode = createToothGeo(width: w, height: h); lNode.position = SCNVector3(-xCursor, 0, 0); lNode.name = "T_\(def.id)_L"; root.addChildNode(lNode)
            xCursor += w
        }
        return root
    }
    
    private func createToothGeo(width: CGFloat, height: CGFloat) -> SCNNode {
        let path = NSBezierPath(roundedRect: CGRect(x: -width/2, y: -height/2, width: width, height: height), xRadius: width*0.3, yRadius: width*0.3)
        let shape = SCNShape(path: path, extrusionDepth: width*0.2); shape.chamferRadius = width*0.05
        let mat = SCNMaterial(); mat.diffuse.contents = NSColor(white: 1.0, alpha: 0.8)
        return SCNNode(geometry: shape)
    }
    
    private func updateGrid(root: SCNNode) {
        let name = "GOLDEN_GRID"
        var gridNode = root.childNode(withName: name, recursively: false)
        if showGrid {
            if gridNode == nil {
                let grid = SCNNode()
                let mat = SCNMaterial(); mat.diffuse.contents = NSColor.cyan
                let lineH = SCNPlane(width: 0.0005, height: 0.1); lineH.materials = [mat]
                let cW: CGFloat = 0.0085; let lW = cW * 0.618; let offsets = [0, cW, cW + lW]
                for x in offsets {
                    let rL = SCNNode(geometry: lineH); rL.position.x = x; grid.addChildNode(rL)
                    let lL = SCNNode(geometry: lineH); lL.position.x = -x; grid.addChildNode(lL)
                }
                grid.name = name; root.addChildNode(grid); gridNode = grid
            }
            gridNode?.position = root.childNode(withName: "SMILE_TEMPLATE", recursively: false)?.position ?? SCNVector3Zero
            gridNode?.position.z += 0.005
        } else {
            gridNode?.removeFromParentNode()
        }
    }
}

class EditorView: SCNView {
    var currentMode: DesignMode = .analysis
    var activeLandmarkType: LandmarkType?
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    var currentToothStates: [String: ToothState] = [:]
    
    private var selectedToothNode: SCNNode?
    private var lastDragPos: CGPoint?
    
    override func mouseDown(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        switch currentMode {
        case .analysis:
            if activeLandmarkType != nil {
                let results = self.hitTest(loc, options: [.rootNode: self.scene!.rootNode, .searchMode: SCNHitTestSearchMode.closest.rawValue])
                if let hit = results.first(where: { $0.node.name == "PATIENT_MODEL" }) {
                    onLandmarkPicked?(hit.worldCoordinates)
                }
            }
        case .design:
            let results = self.hitTest(loc, options: nil)
            if let hit = results.first(where: { $0.node.name?.starts(with: "T_") == true }) {
                self.selectedToothNode = hit.node
                self.allowsCameraControl = false
                onToothSelected?(hit.node.name)
                self.scene?.rootNode.childNode(withName: "SMILE_TEMPLATE", recursively: true)?.childNodes.forEach { $0.geometry?.firstMaterial?.emission.contents = NSColor.black }
                hit.node.geometry?.firstMaterial?.emission.contents = NSColor.blue
            } else {
                self.selectedToothNode = nil
                self.allowsCameraControl = true
                onToothSelected?(nil)
                self.scene?.rootNode.childNode(withName: "SMILE_TEMPLATE", recursively: true)?.childNodes.forEach { $0.geometry?.firstMaterial?.emission.contents = NSColor.black }
                super.mouseDown(with: event)
            }
        }
        lastDragPos = loc
    }
    
    override func mouseDragged(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        if currentMode == .design, let tooth = selectedToothNode, let name = tooth.name, let last = lastDragPos {
            let deltaX = Float(loc.x - last.x)
            let deltaY = Float(loc.y - last.y)
            var state = currentToothStates[name] ?? ToothState()
            state.positionOffset.x += deltaX * 0.05
            state.positionOffset.y -= deltaY * 0.05
            onToothTransformChange?(name, state)
            lastDragPos = loc
        } else {
            super.mouseDragged(with: event)
        }
        lastDragPos = loc
    }
    override func mouseUp(with event: NSEvent) { super.mouseUp(with: event) }
}
