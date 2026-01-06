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
    var isPlacingLandmarks: Bool
    var onLandmarkPicked: ((SCNVector3) -> Void)?
    
    // SNAPSHOT SUPPORT
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
        
        // CHECK SNAPSHOT TRIGGER
        if triggerSnapshot {
            DispatchQueue.main.async {
                let image = view.snapshot()
                onSnapshotTaken?(image)
                triggerSnapshot = false // Reset trigger
            }
        }
        
        guard let root = view.scene?.rootNode else { return }
        
        // 1. SETUP CONTAINER
        var container = root.childNode(withName: "CONTENT_CONTAINER", recursively: false)
        if container == nil {
            container = SCNNode()
            container?.name = "CONTENT_CONTAINER"
            root.addChildNode(container!)
        }
        
        // 2. LOAD MODEL
        if container?.childNode(withName: "PATIENT_MODEL", recursively: true) == nil {
            if let scene = try? SCNScene(url: scanURL, options: nil),
               let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                
                let node = geoNode.clone()
                node.name = "PATIENT_MODEL"
                
                if let geo = node.geometry {
                    let (min, max) = geo.boundingBox
                    let cx = (min.x + max.x) / 2
                    let cy = (min.y + max.y) / 2
                    let cz = (min.z + max.z) / 2
                    node.position = SCNVector3(-cx, -cy, -cz)
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
        
        // 3. CENTERING
        if mode == .analysis, let lastType = LandmarkType.allCases.last(where: { landmarks[$0] != nil }), let worldPos = landmarks[lastType] {
             view.defaultCameraController.target = worldPos
        }
        if mode == .design, let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
             let center = SCNVector3((lC.x+rC.x)/2, (lC.y+rC.y)/2, (lC.z+rC.z)/2)
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
    
    // MARK: - ESTHETIC ANALYSIS
    private func drawEstheticAnalysis(root: SCNNode) {
        let containerName = "ESTHETIC_LINES"
        root.childNode(withName: containerName, recursively: false)?.removeFromParentNode()
        let container = SCNNode(); container.name = containerName; root.addChildNode(container)
        
        func drawLine(_ start: SCNVector3, _ end: SCNVector3, color: NSColor) {
            let indices: [Int32] = [0, 1]
            let source = SCNGeometrySource(vertices: [start, end])
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geo = SCNGeometry(sources: [source], elements: [element])
            geo.firstMaterial?.diffuse.contents = color
            geo.firstMaterial?.emission.contents = color
            container.addChildNode(SCNNode(geometry: geo))
        }
        
        if let lp = landmarks[.leftPupil], let rp = landmarks[.rightPupil] {
            drawLine(lp, rp, color: .yellow)
            let mid = SCNVector3((lp.x+rp.x)/2, (lp.y+rp.y)/2, (lp.z+rp.z)/2)
            let drop = SCNVector3(mid.x, mid.y - 0.20, mid.z)
            drawLine(mid, drop, color: .cyan)
        }
        
        if let gl = landmarks[.glabella], let sn = landmarks[.subnasale], let me = landmarks[.menton] {
            let w: CGFloat = 0.06
            drawLine(SCNVector3(gl.x-w, gl.y, gl.z), SCNVector3(gl.x+w, gl.y, gl.z), color: .white)
            drawLine(SCNVector3(sn.x-w, sn.y, sn.z), SCNVector3(sn.x+w, sn.y, sn.z), color: .white)
            drawLine(SCNVector3(me.x-w, me.y, me.z), SCNVector3(me.x+w, me.y, me.z), color: .white)
        }
        
        if let mid = landmarks[.midline], let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
            let dx = rC.x - lC.x; let dy = rC.y - lC.y
            let archWidth = CGFloat(sqrt(dx*dx + dy*dy))
            let unit = archWidth / 6.472
            let yTop = mid.y + 0.005; let yBot = mid.y - 0.010; let z = mid.z
            
            let wCent = unit * 1.618
            drawLine(SCNVector3(mid.x, yTop, z), SCNVector3(mid.x, yBot, z), color: .red)
            drawLine(SCNVector3(mid.x + wCent, yTop, z), SCNVector3(mid.x + wCent, yBot, z), color: .red)
            drawLine(SCNVector3(mid.x - wCent, yTop, z), SCNVector3(mid.x - wCent, yBot, z), color: .red)
            
            let wLat = wCent + (unit * 1.0)
            drawLine(SCNVector3(mid.x + wLat, yTop, z), SCNVector3(mid.x + wLat, yBot, z), color: .blue)
            drawLine(SCNVector3(mid.x - wLat, yTop, z), SCNVector3(mid.x - wLat, yBot, z), color: .blue)
            
            let wCan = wLat + (unit * 0.618)
            drawLine(SCNVector3(mid.x + wCan, yTop, z), SCNVector3(mid.x + wCan, yBot, z), color: .green)
            drawLine(SCNVector3(mid.x - wCan, yTop, z), SCNVector3(mid.x - wCan, yBot, z), color: .green)
        }
        
        if let sn = landmarks[.subnasale], let me = landmarks[.menton], let st = landmarks[.upperLipCenter] {
            drawLine(sn, me, color: .gray)
            let w: CGFloat = 0.03
            drawLine(SCNVector3(st.x - w, st.y, st.z), SCNVector3(st.x + w, st.y, st.z), color: .magenta)
        }
    }
    
    // MARK: - Landmarks
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
            let node = SCNNode(geometry: sphere)
            node.position = pos
            container.addChildNode(node)
        }
    }
    
    // MARK: - Smile Template
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
            var baseScale: CGFloat = 1.0
            
            if let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
                let cx = (lC.x + rC.x) / 2
                let cy = (lC.y + rC.y) / 2
                let cz = (lC.z + rC.z) / 2
                basePos = SCNVector3(cx, cy, cz)
                
                if let mid = landmarks[.midline] { basePos.x = mid.x }
                if let lip = landmarks[.upperLipCenter] { basePos.y = lip.y - 0.002 }
                
                let dx = rC.x - lC.x
                let dy = rC.y - lC.y
                let dist = sqrt(dx*dx + dy*dy)
                baseScale = CGFloat(dist) * 15.0
            }
            
            let finalScale = baseScale * CGFloat(smileParams.scale)
            templateNode?.scale = SCNVector3(finalScale, finalScale, finalScale)
            
            let px = CGFloat(basePos.x) + CGFloat(smileParams.posX) * 0.05
            let py = CGFloat(basePos.y) + CGFloat(smileParams.posY) * 0.05
            let pz = CGFloat(basePos.z) + CGFloat(smileParams.posZ) * 0.05
            templateNode?.position = SCNVector3(px, py, pz)
            
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
                
                tooth.position = SCNVector3(tX, tY, tZ)
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
