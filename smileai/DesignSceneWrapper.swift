import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

struct SmileTemplateParams {
    var posX: Float
    var posY: Float
    var posZ: Float
    var scale: Float
    var curve: Float
    var length: Float
    var ratio: Float
}

struct DesignSceneWrapper: NSViewRepresentable {
    let scanURL: URL
    let mode: DesignMode
    
    var showSmileTemplate: Bool
    var smileParams: SmileTemplateParams
    
    var toothStates: [String: ToothState]
    var onToothSelected: ((String?) -> Void)?
    var onToothTransformChange: ((String, ToothState) -> Void)?
    
    var landmarks: [LandmarkType: SCNVector3]
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    
    @Binding var triggerSnapshot: Bool
    var onSnapshotTaken: ((NSImage) -> Void)?
    
    var showGrid: Bool
    var onModelLoaded: ((_ bounds: (min: SCNVector3, max: SCNVector3)) -> Void)?
    
    func makeNSView(context: Context) -> EditorView {
        let view = EditorView()
        view.defaultCameraController.interactionMode = .orbitArcball
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.automaticTarget = false
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
        view.isPlacingLandmarks = isPlacingLandmarks
        view.onLandmarkPicked = onLandmarkPicked
        
        // Snapshot Logic
        if triggerSnapshot {
            DispatchQueue.main.async {
                let scaleFactor: CGFloat = 4.0
                let currentSize = view.bounds.size
                let targetSize = CGSize(width: currentSize.width * scaleFactor, height: currentSize.height * scaleFactor)
                
                let renderer = SCNRenderer(device: view.device, options: nil)
                renderer.scene = view.scene
                renderer.pointOfView = view.pointOfView
                renderer.autoenablesDefaultLighting = true
                
                let image = renderer.snapshot(atTime: 0, with: targetSize, antialiasingMode: .multisampling4X)
                onSnapshotTaken?(image)
                
                DispatchQueue.main.async {
                    triggerSnapshot = false
                }
            }
        }
        
        guard let root = view.scene?.rootNode else { return }
        
        // 1. Container Setup
        var container = root.childNode(withName: "CONTENT_CONTAINER", recursively: false)
        if container == nil {
            container = SCNNode()
            container?.name = "CONTENT_CONTAINER"
            root.addChildNode(container!)
        }
        
        // 2. Load Patient Model
        if container?.childNode(withName: "PATIENT_MODEL", recursively: true) == nil {
            if let scene = try? SCNScene(url: scanURL, options: nil),
               let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                
                let node = geoNode.clone()
                node.name = "PATIENT_MODEL"
                
                if let geo = node.geometry {
                    let (min, max) = geo.boundingBox
                    // Explicit cast to CGFloat to fix ambiguity
                    let cx = CGFloat((min.x + max.x) / 2)
                    let cy = CGFloat((min.y + max.y) / 2)
                    let cz = CGFloat((min.z + max.z) / 2)
                    
                    // Center the model
                    node.position = SCNVector3(x: -cx, y: -cy, z: -cz)
                }
                
                node.geometry?.materials.forEach { mat in
                    mat.lightingModel = .lambert
                    mat.isDoubleSided = true
                    mat.specular.contents = NSColor.black
                    if mat.diffuse.contents == nil {
                        mat.diffuse.contents = NSColor(calibratedRed: 0.9, green: 0.85, blue: 0.8, alpha: 1.0)
                    }
                }
                
                container?.addChildNode(node)
                
                DispatchQueue.main.async {
                    view.defaultCameraController.target = SCNVector3Zero
                    view.defaultCameraController.frameNodes([container!])
                }
            }
        }
        
        // 3. Camera Centering
        if mode == .analysis, let lastType = LandmarkType.allCases.last(where: { landmarks[$0] != nil }), let worldPos = landmarks[lastType] {
             view.defaultCameraController.target = worldPos
        }
        if mode == .design, let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
             let center = SCNVector3(x: (lC.x+rC.x)/2, y: (lC.y+rC.y)/2, z: (lC.z+rC.z)/2)
             view.defaultCameraController.target = center
        }
        
        updateSmileTemplate(root: root)
        updateLandmarkVisuals(root: root)
        drawEstheticAnalysis(root: root)
        updateGrid(root: root)
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findFirstGeometryNode(in: child) { return found }
        }
        return nil
    }
    
    // MARK: - SMILE TEMPLATE UPDATES
    private func updateSmileTemplate(root: SCNNode) {
        let name = "SMILE_TEMPLATE"
        var templateNode = root.childNode(withName: name, recursively: false)
        
        if showSmileTemplate {
            if templateNode == nil {
                templateNode = createProceduralArch()
                templateNode?.name = name
                root.addChildNode(templateNode!)
            }
            
            // Positioning Logic
            var basePos = SCNVector3Zero
            
            if let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
                let cx = (lC.x + rC.x) / 2
                let cy = (lC.y + rC.y) / 2
                let cz = (lC.z + rC.z) / 2
                basePos = SCNVector3(x: cx, y: cy, z: cz)
                
                if let lipZ = landmarks[.upperLipCenter]?.z {
                    basePos.z = lipZ + 0.005
                } else {
                    basePos.z += 0.02
                }
                
                if let mid = landmarks[.midline] { basePos.x = mid.x }
                if let lip = landmarks[.upperLipCenter] { basePos.y = lip.y - 0.002 }
                
                let dx = rC.x - lC.x
                let dy = rC.y - lC.y
                let dist = sqrt(dx*dx + dy*dy)
                
                let finalScale = CGFloat(dist) * 15.0 * CGFloat(smileParams.scale)
                templateNode?.scale = SCNVector3(x: finalScale, y: finalScale, z: finalScale)
            }
            
            let px = CGFloat(basePos.x) + CGFloat(smileParams.posX) * 0.05
            let py = CGFloat(basePos.y) + CGFloat(smileParams.posY) * 0.05
            let pz = CGFloat(basePos.z) + CGFloat(smileParams.posZ) * 0.05
            templateNode?.position = SCNVector3(x: px, y: py, z: pz)
            
            if let lp = landmarks[.leftPupil], let rp = landmarks[.rightPupil] {
                let dy = rp.y - lp.y
                let dx = rp.x - lp.x
                let angle = atan2(dy, dx)
                templateNode?.eulerAngles.z = CGFloat(angle)
            }
            
            templateNode?.childNodes.forEach { tooth in
                guard let toothName = tooth.name else { return }
                
                let xVal = CGFloat(tooth.position.x)
                let curveZ = pow(xVal * 5.0, 2) * CGFloat(smileParams.curve) * 0.5
                let state = toothStates[toothName] ?? ToothState()
                
                let tX = xVal + CGFloat(state.positionOffset.x) * 0.01
                let tY = 0.0 + CGFloat(state.positionOffset.y) * 0.01
                let tZ = curveZ + CGFloat(state.positionOffset.z) * 0.01
                
                tooth.position = SCNVector3(x: tX, y: tY, z: tZ)
                tooth.eulerAngles = SCNVector3(x: 0, y: 0, z: CGFloat(state.rotation.z))
                
                let sRatio = CGFloat(smileParams.ratio) * CGFloat(state.scale)
                let sLength = CGFloat(smileParams.length) * CGFloat(state.scale)
                tooth.scale = SCNVector3(x: sRatio, y: sLength, z: 1.0)
                
                tooth.geometry?.firstMaterial?.readsFromDepthBuffer = false
                tooth.renderingOrder = 2000
                
                if tooth.geometry?.firstMaterial?.emission.contents as? NSColor != NSColor.blue {
                    tooth.geometry?.firstMaterial?.emission.contents = NSColor.black
                }
            }
        } else {
            templateNode?.removeFromParentNode()
        }
    }
    
    // MARK: - ARCH GENERATION
    private func createProceduralArch() -> SCNNode {
        let root = SCNNode()
        let baseW: CGFloat = 0.0085
        let definitions: [(id: Int, wRatio: CGFloat, hRatio: CGFloat, type: String)] = [
            (1, 1.0, 1.0, "Central"),
            (2, 0.75, 0.85, "Lateral"),
            (3, 0.85, 0.95, "Canine")
        ]
        
        var xCursor: CGFloat = baseW / 2.0
        
        for def in definitions {
            let w = baseW * def.wRatio
            let h = baseW * 1.2 * def.hRatio
            let rNode: SCNNode
            let lNode: SCNNode
            
            rNode = createToothGeo(width: w, height: h)
            lNode = createToothGeo(width: w, height: h)
            
            rNode.position = SCNVector3(x: xCursor, y: 0, z: 0)
            rNode.name = "T_\(def.id)_R"
            
            lNode.position = SCNVector3(x: -xCursor, y: 0, z: 0)
            lNode.name = "T_\(def.id)_L"
            
            root.addChildNode(rNode)
            root.addChildNode(lNode)
            xCursor += w
        }
        return root
    }
    
    private func createToothGeo(width: CGFloat, height: CGFloat) -> SCNNode {
        let path = NSBezierPath(roundedRect: CGRect(x: -width/2, y: -height/2, width: width, height: height), xRadius: width*0.3, yRadius: width*0.3)
        let shape = SCNShape(path: path, extrusionDepth: width*0.2)
        shape.chamferRadius = width*0.05
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(white: 1.0, alpha: 0.8)
        return SCNNode(geometry: shape)
    }
    
    // MARK: - VISUALS
    private func drawEstheticAnalysis(root: SCNNode) {
        let containerName = "ESTHETIC_LINES"
        root.childNode(withName: containerName, recursively: false)?.removeFromParentNode()
        let container = SCNNode()
        container.name = containerName
        root.addChildNode(container)
        
        var safeZ: CGFloat = 0.05
        let protrusions = [landmarks[.subnasale], landmarks[.upperLipCenter], landmarks[.lowerLipCenter], landmarks[.menton]]
        if let maxZ = protrusions.compactMap({ $0?.z }).max() {
            safeZ = CGFloat(maxZ) + 0.015
        } else if let c1 = landmarks[.leftCanine]?.z, let c2 = landmarks[.rightCanine]?.z {
            safeZ = CGFloat(max(c1, c2)) + 0.03
        }
        
        func drawLine(_ start: SCNVector3, _ end: SCNVector3, color: NSColor) {
            let p1 = SCNVector3(x: CGFloat(start.x), y: CGFloat(start.y), z: safeZ)
            let p2 = SCNVector3(x: CGFloat(end.x), y: CGFloat(end.y), z: safeZ)
            
            let indices: [Int32] = [0, 1]
            let source = SCNGeometrySource(vertices: [p1, p2])
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geo = SCNGeometry(sources: [source], elements: [element])
            
            geo.firstMaterial?.diffuse.contents = color
            geo.firstMaterial?.emission.contents = color
            geo.firstMaterial?.readsFromDepthBuffer = false
            geo.firstMaterial?.writesToDepthBuffer = false
            
            let node = SCNNode(geometry: geo)
            node.renderingOrder = 1000
            container.addChildNode(node)
        }
        
        // Lines Logic
        if let lp = landmarks[.leftPupil], let rp = landmarks[.rightPupil] {
            drawLine(lp, rp, color: .yellow)
            let mid = SCNVector3(x: (lp.x+rp.x)/2, y: (lp.y+rp.y)/2, z: 0)
            let drop = SCNVector3(x: mid.x, y: mid.y - 0.20, z: 0)
            drawLine(mid, drop, color: .cyan)
        }
        
        if let gl = landmarks[.glabella], let sn = landmarks[.subnasale], let me = landmarks[.menton] {
            let w: CGFloat = 0.06
            drawLine(SCNVector3(x: gl.x-w, y: gl.y, z: 0), SCNVector3(x: gl.x+w, y: gl.y, z: 0), color: .white)
            drawLine(SCNVector3(x: sn.x-w, y: sn.y, z: 0), SCNVector3(x: sn.x+w, y: sn.y, z: 0), color: .white)
            drawLine(SCNVector3(x: me.x-w, y: me.y, z: 0), SCNVector3(x: me.x+w, y: me.y, z: 0), color: .white)
        }
        
        // Golden Percentage (23-15-12)
        if let mid = landmarks[.midline], let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
            let dx = rC.x - lC.x
            let dy = rC.y - lC.y
            let archWidth = CGFloat(sqrt(dx*dx + dy*dy))
            let yTop = mid.y + 0.005
            let yBot = mid.y - 0.010
            
            let wCent = archWidth * 0.23
            let wLatCumulative = archWidth * 0.38
            let wCanCumulative = archWidth * 0.50
            
            drawLine(SCNVector3(x: CGFloat(mid.x), y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x), y: CGFloat(yBot), z: 0), color: .red)
            drawLine(SCNVector3(x: CGFloat(mid.x)+wCent, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)+wCent, y: CGFloat(yBot), z: 0), color: .red)
            drawLine(SCNVector3(x: CGFloat(mid.x)-wCent, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)-wCent, y: CGFloat(yBot), z: 0), color: .red)
            
            drawLine(SCNVector3(x: CGFloat(mid.x)+wLatCumulative, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)+wLatCumulative, y: CGFloat(yBot), z: 0), color: .blue)
            drawLine(SCNVector3(x: CGFloat(mid.x)-wLatCumulative, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)-wLatCumulative, y: CGFloat(yBot), z: 0), color: .blue)
            
            drawLine(SCNVector3(x: CGFloat(mid.x)+wCanCumulative, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)+wCanCumulative, y: CGFloat(yBot), z: 0), color: .green)
            drawLine(SCNVector3(x: CGFloat(mid.x)-wCanCumulative, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)-wCanCumulative, y: CGFloat(yBot), z: 0), color: .green)
        }
        
        if let sn = landmarks[.subnasale], let me = landmarks[.menton], let st = landmarks[.upperLipCenter] {
            drawLine(sn, me, color: .gray)
            let w: CGFloat = 0.03
            drawLine(SCNVector3(x: CGFloat(st.x) - w, y: CGFloat(st.y), z: 0), SCNVector3(x: CGFloat(st.x) + w, y: CGFloat(st.y), z: 0), color: .magenta)
        }
    }
    
    private func updateLandmarkVisuals(root: SCNNode) {
        let containerName = "LANDMARKS_CONTAINER"
        root.childNode(withName: containerName, recursively: false)?.removeFromParentNode()
        let container = SCNNode()
        container.name = containerName
        root.addChildNode(container)
        
        for (type, pos) in landmarks {
            let sphere = SCNSphere(radius: 0.0015)
            var color: NSColor = .blue
            switch type {
            case .rightPupil, .leftPupil: color = .yellow
            case .midline, .glabella: color = .cyan
            case .rightCommissure, .leftCommissure: color = .green
            case .subnasale, .menton: color = .white
            default: color = .blue
            }
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.emission.contents = color
            sphere.firstMaterial?.readsFromDepthBuffer = false
            let node = SCNNode(geometry: sphere)
            // Explicit cast
            node.position = pos
            node.renderingOrder = 1001
            container.addChildNode(node)
        }
    }
    
    private func updateGrid(root: SCNNode) {
        let name = "GOLDEN_GRID"
        var gridNode = root.childNode(withName: name, recursively: false)
        if showGrid {
            if gridNode == nil {
                let grid = SCNNode()
                let mat = SCNMaterial()
                mat.diffuse.contents = NSColor.cyan
                let lineH = SCNPlane(width: 0.0005, height: 0.1)
                lineH.materials = [mat]
                let cW: CGFloat = 0.0085
                let lW = cW * 0.618
                let offsets = [0, cW, cW + lW]
                for x in offsets {
                    let rL = SCNNode(geometry: lineH)
                    rL.position.x = x
                    grid.addChildNode(rL)
                    let lL = SCNNode(geometry: lineH)
                    lL.position.x = -x
                    grid.addChildNode(lL)
                }
                grid.name = name
                root.addChildNode(grid)
                gridNode = grid
            }
            // Position near template
            let templatePos = root.childNode(withName: "SMILE_TEMPLATE", recursively: false)?.position ?? SCNVector3Zero
            gridNode?.position = templatePos
            gridNode?.position.z += 0.005
        } else {
            gridNode?.removeFromParentNode()
        }
    }
}

// MARK: - EDITOR VIEW
class EditorView: SCNView {
    var currentMode: DesignMode = .analysis
    var activeLandmarkType: LandmarkType?
    var isPlacingLandmarks: Bool = false
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
            if isPlacingLandmarks && activeLandmarkType != nil {
                let results = self.hitTest(loc, options: [.rootNode: self.scene!.rootNode, .searchMode: SCNHitTestSearchMode.closest.rawValue])
                if let hit = results.first(where: { $0.node.name == "PATIENT_MODEL" }) {
                    onLandmarkPicked?(hit.worldCoordinates)
                }
            } else {
                super.mouseDown(with: event)
            }
        case .design:
            let results = self.hitTest(loc, options: nil)
            if let hit = results.first(where: { $0.node.name?.starts(with: "T_") == true }) {
                self.selectedToothNode = hit.node
                self.allowsCameraControl = false
                onToothSelected?(hit.node.name)
                
                // Visual Selection
                self.scene?.rootNode.childNode(withName: "SMILE_TEMPLATE", recursively: true)?.childNodes.forEach {
                    $0.geometry?.firstMaterial?.emission.contents = NSColor.black
                }
                hit.node.geometry?.firstMaterial?.emission.contents = NSColor.blue
            } else {
                self.selectedToothNode = nil
                self.allowsCameraControl = true
                onToothSelected?(nil)
                
                // Deselect
                self.scene?.rootNode.childNode(withName: "SMILE_TEMPLATE", recursively: true)?.childNodes.forEach {
                    $0.geometry?.firstMaterial?.emission.contents = NSColor.black
                }
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
            
            // Adjust State
            state.positionOffset.x += deltaX * 0.05
            state.positionOffset.y -= deltaY * 0.05
            onToothTransformChange?(name, state)
        } else {
            super.mouseDragged(with: event)
        }
        lastDragPos = loc
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }
}
