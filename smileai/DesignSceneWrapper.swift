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
    let mode: DesignMode // Now using Enum
    
    @Binding var triggerDelete: Bool
    var onDelete: ((Set<Int>) -> Void)?
    
    var showSmileTemplate: Bool
    var smileParams: SmileTemplateParams
    
    // Interactive State
    var toothStates: [String: ToothState]
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    
    // NEW: Landmarks Support
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
        // Sync State
        view.currentMode = mode
        view.onToothSelected = onToothSelected
        view.onToothTransformChange = onToothTransformChange
        view.currentToothStates = toothStates
        
        // Pass Landmark callbacks
        view.activeLandmarkType = activeLandmarkType
        view.onLandmarkPicked = onLandmarkPicked
        
        // Handle Deletion
        if triggerDelete {
            let indices = view.selectedIndices
            if !indices.isEmpty {
                view.clearSelection()
                DispatchQueue.main.async { onDelete?(indices); triggerDelete = false }
            } else {
                DispatchQueue.main.async { triggerDelete = false }
            }
        }
        
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
                
                if let geo = node.geometry {
                    if geo.sources(for: .tangent).isEmpty {
                        let mdlMesh = MDLMesh(scnGeometry: geo)
                        mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
                        node.geometry = SCNGeometry(mdlMesh: mdlMesh)
                    }
                    node.geometry?.materials.forEach { mat in
                        mat.lightingModel = .physicallyBased
                        mat.isDoubleSided = true
                        mat.roughness.contents = 0.5
                        mat.metalness.contents = 0.0
                        if mat.diffuse.contents == nil {
                            mat.diffuse.contents = NSColor(calibratedRed: 0.9, green: 0.85, blue: 0.8, alpha: 1.0)
                        }
                    }
                }
                
                root.addChildNode(node)
                view.prepareForPainting(node: node)
                
                DispatchQueue.main.async {
                    self.onModelLoaded?((min: node.boundingBox.min, max: node.boundingBox.max))
                    view.defaultCameraController.target = SCNVector3Zero
                    view.defaultCameraController.frameNodes([node])
                }
            }
        }
        
        // Update Visuals
        updateSmileTemplate(root: root, patientNode: root.childNode(withName: "PATIENT_MODEL", recursively: true))
        updateLandmarkVisuals(root: root) // Draw spheres
        updateGrid(root: root)
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findFirstGeometryNode(in: child) { return found }
        }
        return nil
    }
    
    // MARK: - Landmarks Visualization
    private func updateLandmarkVisuals(root: SCNNode) {
        let containerName = "LANDMARKS_CONTAINER"
        root.childNode(withName: containerName, recursively: false)?.removeFromParentNode()
        
        let container = SCNNode()
        container.name = containerName
        root.addChildNode(container)
        
        for (type, pos) in landmarks {
            let sphere = SCNSphere(radius: 0.0015) // 1.5mm dot
            sphere.firstMaterial?.diffuse.contents = (type == .midline) ? NSColor.green : NSColor.blue
            sphere.firstMaterial?.emission.contents = (type == .midline) ? NSColor.green : NSColor.blue
            let node = SCNNode(geometry: sphere)
            node.position = pos
            container.addChildNode(node)
        }
    }
    
    // MARK: - Smile Template (Same logic as before)
    private func updateSmileTemplate(root: SCNNode, patientNode: SCNNode?) {
        let name = "SMILE_TEMPLATE"
        var templateNode = root.childNode(withName: name, recursively: false)
        
        if showSmileTemplate {
            if templateNode == nil {
                templateNode = createProceduralArch()
                templateNode?.name = name
                root.addChildNode(templateNode!)
            }
            // ... (Use same transform logic as previous phase)
            // Ideally, here we would USE landmarks to position this!
            // For now, keep existing manual sliders + individual teeth logic.
            
            var unitScale: CGFloat = 1.0
            if let pNode = patientNode {
                let (min, max) = pNode.boundingBox
                if (max.x - min.x) > 10 { unitScale = 1000.0 }
            }
            let moveScale = unitScale * 0.5
            templateNode?.position = SCNVector3(CGFloat(smileParams.posX) * moveScale, CGFloat(smileParams.posY) * moveScale, CGFloat(smileParams.posZ) * moveScale)
            let s = CGFloat(smileParams.scale) * unitScale
            templateNode?.scale = SCNVector3(s, s, s)
            
            templateNode?.childNodes.forEach { tooth in
                guard let toothName = tooth.name else { return }
                let xVal = Float(tooth.position.x)
                let curveZ = pow(xVal * 5.0, 2) * smileParams.curve * 0.5
                let state = toothStates[toothName] ?? ToothState()
                
                tooth.position.y = 0 + CGFloat(state.positionOffset.y) * 0.01
                tooth.position.x = CGFloat(xVal) + CGFloat(state.positionOffset.x) * 0.01
                tooth.position.z = CGFloat(curveZ) + CGFloat(state.positionOffset.z) * 0.01
                tooth.eulerAngles = SCNVector3(0, 0, CGFloat(state.rotation.z))
                tooth.scale = SCNVector3(CGFloat(smileParams.ratio) * CGFloat(state.scale), CGFloat(smileParams.length) * CGFloat(state.scale), 1.0)
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
        let mat = SCNMaterial(); mat.diffuse.contents = NSColor(white: 1.0, alpha: 0.7)
        return SCNNode(geometry: shape)
    }
    
    private func updateGrid(root: SCNNode) { /* Same as before */ }
}

// MARK: - Editor View

class EditorView: SCNView {
    var currentMode: DesignMode = .cleanup
    
    // Landmark Callback
    var activeLandmarkType: LandmarkType?
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    
    // Other Callbacks
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    var currentToothStates: [String: ToothState] = [:]
    
    private var selectedToothNode: SCNNode?
    private var lastDragPos: CGPoint?
    
    // Paint
    private var geometryNode: SCNNode?
    struct FloatColor { var r, g, b, a: Float }
    private var vertexColors: [FloatColor] = []
    public var selectedIndices: Set<Int> = []
    var isPaintMode: Bool = false
    
    func prepareForPainting(node: SCNNode) {
        self.geometryNode = node
        guard let geo = node.geometry, let src = geo.sources(for: .vertex).first else { return }
        self.vertexColors = Array(repeating: FloatColor(r: 1, g: 1, b: 1, a: 1), count: src.vectorCount)
        updateColorGeometry()
    }
    
    func clearSelection() {
        selectedIndices.removeAll()
        vertexColors = vertexColors.map { _ in FloatColor(r: 1, g: 1, b: 1, a: 1) }
        updateColorGeometry()
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = self.convert(event.locationInWindow, from: nil)
        
        switch currentMode {
        case .cleanup:
            // Paint Mode
            if isPaintMode { paint(event: event) }
            
        case .analysis:
            // --- LANDMARK PICKING ---
            // If the UI is asking for a landmark, raycast to find it
            if activeLandmarkType != nil {
                let results = self.hitTest(loc, options: [.rootNode: self.scene!.rootNode, .searchMode: SCNHitTestSearchMode.closest.rawValue])
                // Hit the patient model?
                if let hit = results.first(where: { $0.node.name == "PATIENT_MODEL" }) {
                    // Report the WORLD position
                    onLandmarkPicked?(hit.worldCoordinates)
                }
            }
            
        case .design:
            // Tooth Selection Mode
            let results = self.hitTest(loc, options: nil)
            if let hit = results.first(where: { $0.node.name?.starts(with: "T_") == true }) {
                self.selectedToothNode = hit.node
                self.allowsCameraControl = false
                onToothSelected?(hit.node.name)
                // Visual Highlight
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
        
        if currentMode == .cleanup {
            paint(event: event)
        } else if currentMode == .design, let tooth = selectedToothNode, let name = tooth.name, let last = lastDragPos {
            // Tooth Dragging
            let deltaX = Float(loc.x - last.x)
            let deltaY = Float(loc.y - last.y)
            var state = currentToothStates[name] ?? ToothState()
            state.positionOffset.x += deltaX * 0.05
            state.positionOffset.y += deltaY * 0.05
            onToothTransformChange?(name, state)
            lastDragPos = loc
        } else {
            super.mouseDragged(with: event)
        }
        lastDragPos = loc
    }
    
    override func mouseUp(with event: NSEvent) {
        // Re-enable camera if we released a tooth
        if currentMode == .design && selectedToothNode != nil {
            // allowsCameraControl = true // Optional: Keep locked or unlock
        }
        super.mouseUp(with: event)
    }
    
    // (Paint functions paint, updateColorGeometry same as before)
    private func paint(event: NSEvent) {
        guard let node = geometryNode, let geo = node.geometry else { return }
        let loc = self.convert(event.locationInWindow, from: nil)
        let results = self.hitTest(loc, options: [.rootNode: node, .searchMode: SCNHitTestSearchMode.closest.rawValue])
        guard let hit = results.first else { return }
        let localPoint = hit.localCoordinates
        let bounds = node.boundingBox
        let scale = CGFloat(bounds.max.x - bounds.min.x)
        let r = max(scale * 0.03, 0.002)
        let rSq = r*r
        guard let vertexSource = geo.sources(for: .vertex).first else { return }
        vertexSource.data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            let stride = vertexSource.dataStride / 4
            let offset = vertexSource.dataOffset / 4
            var changed = false
            for i in 0..<vertexSource.vectorCount {
                if selectedIndices.contains(i) { continue }
                let x = CGFloat(floatBuffer[i * stride + offset])
                let y = CGFloat(floatBuffer[i * stride + offset + 1])
                let z = CGFloat(floatBuffer[i * stride + offset + 2])
                let dx = x - localPoint.x; let dy = y - localPoint.y; let dz = z - localPoint.z
                if (dx*dx + dy*dy + dz*dz) < rSq {
                    selectedIndices.insert(i)
                    vertexColors[i] = FloatColor(r: 1, g: 0, b: 0, a: 1)
                    changed = true
                }
            }
            if changed { updateColorGeometry() }
        }
    }
    
    private func updateColorGeometry() {
        guard let node = geometryNode, let geo = node.geometry else { return }
        let data = Data(bytes: vertexColors, count: vertexColors.count * MemoryLayout<FloatColor>.size)
        let colorSource = SCNGeometrySource(data: data, semantic: .color, vectorCount: vertexColors.count, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<FloatColor>.size)
        let otherSources = geo.sources.filter { $0.semantic != .color }
        let newGeo = SCNGeometry(sources: otherSources + [colorSource], elements: geo.elements)
        newGeo.materials = geo.materials
        node.geometry = newGeo
    }
}
