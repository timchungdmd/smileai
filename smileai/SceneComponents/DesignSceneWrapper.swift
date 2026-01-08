import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

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
    var onModelLoaded: ((_ bounds: (min: SCNVector3, max: SCNVector3)) -> Void)? = nil
    
    var toothLibrary: [String: URL] = [:]
    var libraryID: UUID = UUID()
    
    @Binding var isDrawingCurve: Bool
    var isCurveLocked: Bool
    @Binding var customCurvePoints: [SCNVector3]
    
    func makeNSView(context: Context) -> EditorView {
        let view = EditorView()
        view.defaultCameraController.interactionMode = .orbitArcball
        view.defaultCameraController.inertiaEnabled = true
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        view.scene = SCNScene()
        return view
    }
    
    func updateNSView(_ view: EditorView, context: Context) {
        view.currentMode = mode
        view.onToothSelected = { name in self.onToothSelected?(name) }
        view.onToothTransformChange = onToothTransformChange
        view.currentToothStates = toothStates
        view.activeLandmarkType = activeLandmarkType
        view.isPlacingLandmarks = isPlacingLandmarks
        view.onLandmarkPicked = onLandmarkPicked
        
        view.isDrawingCurve = isDrawingCurve
        view.isCurveLocked = isCurveLocked
        
        view.onCurveUpdated = { points in
            DispatchQueue.main.async { self.customCurvePoints = points }
        }
        
        view.onCurveClosed = {
            DispatchQueue.main.async { self.isDrawingCurve = false }
        }
        
        view.setCurvePoints(customCurvePoints)
        
        if triggerSnapshot {
            DispatchQueue.main.async {
                let scale: CGFloat = 4.0
                let size = view.bounds.size
                let target = CGSize(width: size.width * scale, height: size.height * scale)
                let renderer = SCNRenderer(device: view.device, options: nil)
                renderer.scene = view.scene
                renderer.pointOfView = view.pointOfView
                renderer.autoenablesDefaultLighting = true
                let img = renderer.snapshot(atTime: 0, with: target, antialiasingMode: .multisampling4X)
                onSnapshotTaken?(img)
                triggerSnapshot = false
            }
        }
        
        guard let root = view.scene?.rootNode else { return }
        
        setupScene(root, view)
        
        if mode == .analysis, let last = landmarks.values.first {
             view.defaultCameraController.target = last
        } else if mode == .design, let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
             view.defaultCameraController.target = SCNVector3((lC.x+rC.x)/2, (lC.y+rC.y)/2, (lC.z+rC.z)/2)
        }
        
        updateSmileTemplate(root: root)
        updateLandmarkVisuals(root: root)
        drawEstheticAnalysis(root: root)
        updateGrid(root: root)
    }
    
    private func setupScene(_ root: SCNNode, _ view: EditorView) {
        if root.childNode(withName: "CONTENT_CONTAINER", recursively: false) == nil {
            let c = SCNNode(); c.name = "CONTENT_CONTAINER"; root.addChildNode(c)
        }
        
        if root.childNode(withName: "PATIENT_MODEL", recursively: true) == nil {
            let authorized = scanURL.startAccessingSecurityScopedResource()
            defer { if authorized { scanURL.stopAccessingSecurityScopedResource() } }
            
            if let scene = try? SCNScene(url: scanURL, options: nil),
               let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                
                let node = MeshUtils.normalize(geoNode)
                node.name = "PATIENT_MODEL"
                
                // MATERIAL: DENTAL STONE (BEIGE)
                node.geometry?.materials.forEach { mat in
                    mat.isDoubleSided = true
                    
                    let hasTexture = mat.diffuse.contents is NSImage || mat.diffuse.contents is String || mat.diffuse.contents is URL
                    
                    if hasTexture {
                        mat.lightingModel = .physicallyBased
                    } else {
                        // Apply Realistic Stone Material
                        mat.lightingModel = .physicallyBased
                        mat.diffuse.contents = NSColor(calibratedRed: 0.85, green: 0.82, blue: 0.78, alpha: 1.0)
                        mat.roughness.contents = 0.6
                    }
                }
                
                root.addChildNode(node)
                DispatchQueue.main.async { view.defaultCameraController.target = SCNVector3Zero }
            }
        }
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes { if let found = findFirstGeometryNode(in: child) { return found } }
        return nil
    }
    
    private func updateSmileTemplate(root: SCNNode) {
        let name = "SMILE_TEMPLATE"; let nodeID = "\(name)|\(libraryID.uuidString)"
        var templateNode = root.childNode(withName: nodeID, recursively: false)
        root.childNodes.forEach { if $0.name?.starts(with: name) == true && $0.name != nodeID { $0.removeFromParentNode() } }
        if showSmileTemplate {
            if templateNode == nil { templateNode = createProceduralArch(); templateNode?.name = nodeID; root.addChildNode(templateNode!) }
            if !customCurvePoints.isEmpty && customCurvePoints.count > 5 { fitTeethToCustomCurve(templateNode!) }
            else { applyProceduralTransforms(to: templateNode!) }
        } else { templateNode?.removeFromParentNode() }
    }
    
    private func fitTeethToCustomCurve(_ templateNode: SCNNode) {
        var curveLength: CGFloat = 0; var dists: [CGFloat] = [0]
        for i in 0..<customCurvePoints.count-1 {
            let p1 = customCurvePoints[i]; let p2 = customCurvePoints[i+1]
            curveLength += CGFloat(sqrt(pow(p2.x-p1.x, 2) + pow(p2.y-p1.y, 2) + pow(p2.z-p1.z, 2)))
            dists.append(curveLength)
        }
        let scaleToFit = curveLength / 0.045
        let teethOrder = ["T_3_L", "T_2_L", "T_1_L", "T_1_R", "T_2_R", "T_3_R"]
        let step = curveLength / CGFloat(teethOrder.count)
        for (i, toothName) in teethOrder.enumerated() {
            guard let tooth = templateNode.childNode(withName: toothName, recursively: true) else { continue }
            let d = (CGFloat(i) * step) + (step / 2.0)
            if let (pos, tangent) = interpolateCurve(distance: d, totalLength: curveLength, distances: dists) {
                tooth.position = pos
                let up = SCNVector3(0, 1, 0)
                let normal = SCNVector3(tangent.y*up.z - tangent.z*up.y, tangent.z*up.x - tangent.x*up.z, tangent.x*up.y - tangent.y*up.x)
                tooth.look(at: SCNVector3(pos.x+normal.x, pos.y+normal.y, pos.z+normal.z), up: up, localFront: SCNVector3(0,0,1))
                let state = toothStates[toothName] ?? ToothState()
                tooth.localTranslate(by: SCNVector3(CGFloat(state.positionOffset.x)*0.01, CGFloat(state.positionOffset.y)*0.01, CGFloat(state.positionOffset.z)*0.01))
                tooth.eulerAngles.x += CGFloat(state.rotation.x); tooth.eulerAngles.y += CGFloat(state.rotation.y); tooth.eulerAngles.z += CGFloat(state.rotation.z)
                let s = scaleToFit * CGFloat(smileParams.scale)
                tooth.scale = SCNVector3(s * CGFloat(state.scale.x), s * CGFloat(state.scale.y), s * CGFloat(state.scale.z))
            }
        }
    }
    
    private func interpolateCurve(distance: CGFloat, totalLength: CGFloat, distances: [CGFloat]) -> (SCNVector3, SCNVector3)? {
        for i in 0..<distances.count-1 {
            if distance >= distances[i] && distance <= distances[i+1] {
                let t = (distance - distances[i]) / (distances[i+1] - distances[i])
                let p1 = customCurvePoints[i]; let p2 = customCurvePoints[i+1]
                let pos = SCNVector3(CGFloat(p1.x)+CGFloat(p2.x-p1.x)*t, CGFloat(p1.y)+CGFloat(p2.y-p1.y)*t, CGFloat(p1.z)+CGFloat(p2.z-p1.z)*t)
                let dx = CGFloat(p2.x-p1.x); let dy = CGFloat(p2.y-p1.y); let dz = CGFloat(p2.z-p1.z); let len = sqrt(dx*dx+dy*dy+dz*dz)
                return (pos, SCNVector3(dx/len, dy/len, dz/len))
            }
        }
        return nil
    }
    
    private func createProceduralArch() -> SCNNode {
        let root = SCNNode(); let baseW: CGFloat = 0.0085
        let definitions: [(id: Int, wRatio: CGFloat, hRatio: CGFloat, type: String)] = [(1,1.0,1.0,"Central"),(2,0.75,0.85,"Lateral"),(3,0.85,0.95,"Canine")]
        var xCursor: CGFloat = baseW / 2.0
        for def in definitions {
            let w = baseW * def.wRatio
            if let libURL = toothLibrary[def.type], let libNode = loadToothMesh(url: libURL) {
                let rNode = libNode.clone(); let lNode = libNode.clone(); lNode.scale.x *= -1
                rNode.position = SCNVector3(xCursor, 0, 0); rNode.name = "T_\(def.id)_R"
                lNode.position = SCNVector3(-xCursor, 0, 0); lNode.name = "T_\(def.id)_L"
                root.addChildNode(rNode); root.addChildNode(lNode)
            }
            xCursor += w
        }
        if !root.childNodes.isEmpty { applyProceduralTransforms(to: root) }
        return root
    }
    
    private func applyProceduralTransforms(to templateNode: SCNNode) {
        var basePos = SCNVector3Zero
        if let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
            let cx = (lC.x + rC.x) / 2; let cy = (lC.y + rC.y) / 2; let cz = (lC.z + rC.z) / 2; basePos = SCNVector3(x: cx, y: cy, z: cz)
            if let lipZ = landmarks[.upperLipCenter]?.z { basePos.z = lipZ + 0.005 } else { basePos.z += 0.02 }
            if let mid = landmarks[.midline] { basePos.x = mid.x }; if let lip = landmarks[.upperLipCenter] { basePos.y = lip.y - 0.002 }
            let dx = rC.x - lC.x; let dy = rC.y - lC.y; let dist = sqrt(dx*dx + dy*dy)
            let baseScale = CGFloat(dist) * 15.0 * CGFloat(smileParams.scale)
            templateNode.scale = SCNVector3(x: baseScale, y: baseScale, z: baseScale)
        }
        let px = CGFloat(basePos.x) + CGFloat(smileParams.posX) * 0.05; let py = CGFloat(basePos.y) + CGFloat(smileParams.posY) * 0.05; let pz = CGFloat(basePos.z) + CGFloat(smileParams.posZ) * 0.05
        templateNode.position = SCNVector3(x: px, y: py, z: pz)
        if let lp = landmarks[.leftPupil], let rp = landmarks[.rightPupil] { let dy = rp.y - lp.y; let dx = rp.x - lp.x; let angle = atan2(dy, dx); templateNode.eulerAngles.z = CGFloat(angle) }
        templateNode.childNodes.forEach { tooth in
            guard let toothName = tooth.name else { return }
            let xVal = CGFloat(tooth.position.x); let curveZ = pow(xVal * 5.0, 2) * CGFloat(smileParams.curve) * 0.5
            let state = toothStates[toothName] ?? ToothState()
            let tX = xVal + CGFloat(state.positionOffset.x) * 0.01; let tY = 0.0 + CGFloat(state.positionOffset.y) * 0.01; let tZ = curveZ + CGFloat(state.positionOffset.z) * 0.01
            tooth.position = SCNVector3(x: tX, y: tY, z: tZ)
            tooth.eulerAngles = SCNVector3(x: CGFloat(state.rotation.x), y: CGFloat(state.rotation.y), z: CGFloat(state.rotation.z))
            let sRatio = CGFloat(smileParams.ratio) * CGFloat(state.scale.x); let sLength = CGFloat(smileParams.length) * CGFloat(state.scale.y); let sThick = CGFloat(state.scale.z)
            tooth.scale = SCNVector3(x: sRatio, y: sLength, z: sThick)
        }
    }
    
    private func loadToothMesh(url: URL) -> SCNNode? {
        let authorized = url.startAccessingSecurityScopedResource(); defer { if authorized { url.stopAccessingSecurityScopedResource() } }
        guard let scene = try? SCNScene(url: url, options: nil), let geoNode = findFirstGeometryNode(in: scene.rootNode) else { return nil }
        return MeshUtils.normalize(geoNode)
    }
    
    private func drawEstheticAnalysis(root: SCNNode) {
        let containerName = "ESTHETIC_LINES"; root.childNode(withName: containerName, recursively: false)?.removeFromParentNode(); let container = SCNNode(); container.name = containerName; root.addChildNode(container)
        var safeZ: CGFloat = 0.05
        if let c1 = landmarks[.leftCanine]?.z, let c2 = landmarks[.rightCanine]?.z { safeZ = CGFloat(max(c1, c2)) + 0.03 }
        func drawLine(_ start: SCNVector3, _ end: SCNVector3, color: NSColor) { let p1 = SCNVector3(x: CGFloat(start.x), y: CGFloat(start.y), z: safeZ); let p2 = SCNVector3(x: CGFloat(end.x), y: CGFloat(end.y), z: safeZ); let source = SCNGeometrySource(vertices: [p1, p2]); let element = SCNGeometryElement(indices: [0, 1], primitiveType: .line); let geo = SCNGeometry(sources: [source], elements: [element]); geo.firstMaterial?.diffuse.contents = color; container.addChildNode(SCNNode(geometry: geo)) }
        if let lp = landmarks[.leftPupil], let rp = landmarks[.rightPupil] { drawLine(lp, rp, color: .yellow) }
    }
    
    private func updateLandmarkVisuals(root: SCNNode) {
        let containerName = "LANDMARKS_CONTAINER"; root.childNode(withName: containerName, recursively: false)?.removeFromParentNode(); let container = SCNNode(); container.name = containerName; root.addChildNode(container)
        for (type, pos) in landmarks {
            let sphere = SCNSphere(radius: 0.0015); var color: NSColor = .blue
            switch type { case .rightPupil, .leftPupil: color = .yellow; case .midline, .glabella: color = .cyan; case .rightCommissure, .leftCommissure: color = .green; default: color = .blue }
            sphere.firstMaterial?.diffuse.contents = color; let node = SCNNode(geometry: sphere); node.position = pos; node.renderingOrder = 1001; container.addChildNode(node)
        }
    }
    
    private func updateGrid(root: SCNNode) { let name = "GOLDEN_GRID"; var gridNode = root.childNode(withName: name, recursively: false); if showGrid { if gridNode == nil { let grid = SCNNode(); let mat = SCNMaterial(); mat.diffuse.contents = NSColor.cyan; let lineH = SCNPlane(width: 0.0005, height: 0.1); lineH.materials = [mat]; let cW: CGFloat = 0.0085; let lW = cW * 0.618; let offsets = [0, cW, cW + lW]; for x in offsets { let rL = SCNNode(geometry: lineH); rL.position.x = x; grid.addChildNode(rL); let lL = SCNNode(geometry: lineH); lL.position.x = -x; grid.addChildNode(lL) }; grid.name = name; root.addChildNode(grid); gridNode = grid }; gridNode?.position = root.childNode(withName: "SMILE_TEMPLATE", recursively: false)?.position ?? SCNVector3Zero; gridNode?.position.z += 0.005 } else { gridNode?.removeFromParentNode() } }
}
