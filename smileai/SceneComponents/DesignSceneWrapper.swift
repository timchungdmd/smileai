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
    
    // LIBRARY & CURVE
    var toothLibrary: [String: URL] = [:]
    var libraryID: UUID = UUID()
    
    var isDrawingCurve: Bool = false
    @Binding var customCurvePoints: [SCNVector3]
    
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
        
        // Pass drawing state to view
        view.isDrawingCurve = isDrawingCurve
        view.onCurveUpdated = { points in
            DispatchQueue.main.async {
                self.customCurvePoints = points
            }
        }
        
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
                DispatchQueue.main.async { triggerSnapshot = false }
            }
        }
        
        guard let root = view.scene?.rootNode else { return }
        
        // 1. Container
        var container = root.childNode(withName: "CONTENT_CONTAINER", recursively: false)
        if container == nil {
            container = SCNNode(); container?.name = "CONTENT_CONTAINER"; root.addChildNode(container!)
        }
        
        // 2. Patient
        if container?.childNode(withName: "PATIENT_MODEL", recursively: true) == nil {
            if let scene = try? SCNScene(url: scanURL, options: nil), let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                let node = geoNode.clone(); node.name = "PATIENT_MODEL"
                if let geo = node.geometry {
                    let (min, max) = geo.boundingBox
                    let cx = CGFloat((min.x + max.x) / 2); let cy = CGFloat((min.y + max.y) / 2); let cz = CGFloat((min.z + max.z) / 2)
                    node.position = SCNVector3(-cx, -cy, -cz)
                }
                node.geometry?.materials.forEach { mat in mat.lightingModel = .lambert; mat.isDoubleSided = true; mat.specular.contents = NSColor.black; if mat.diffuse.contents == nil { mat.diffuse.contents = NSColor(calibratedRed: 0.9, green: 0.85, blue: 0.8, alpha: 1.0) } }
                container?.addChildNode(node)
                DispatchQueue.main.async { view.defaultCameraController.target = SCNVector3Zero; view.defaultCameraController.frameNodes([container!]) }
            }
        }
        
        // 3. Camera
        if mode == .analysis, let lastType = LandmarkType.allCases.last(where: { landmarks[$0] != nil }), let worldPos = landmarks[lastType] { view.defaultCameraController.target = worldPos }
        if mode == .design, let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
             let center = SCNVector3(x: (lC.x+rC.x)/2, y: (lC.y+rC.y)/2, z: (lC.z+rC.z)/2)
             view.defaultCameraController.target = center
        }
        
        // 4. Updates
        updateSmileTemplate(root: root)
        updateLandmarkVisuals(root: root)
        drawEstheticAnalysis(root: root)
        updateGrid(root: root)
        
        // 5. Draw the custom curve visualization
        drawCustomCurve(root: root)
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes { if let found = findFirstGeometryNode(in: child) { return found } }
        return nil
    }
    
    // MARK: - DRAW CUSTOM CURVE VISUAL
    private func drawCustomCurve(root: SCNNode) {
        let name = "CUSTOM_SMILE_LINE"
        root.childNode(withName: name, recursively: false)?.removeFromParentNode()
        
        guard !customCurvePoints.isEmpty else { return }
        
        // Draw lines
        var indices: [Int32] = []
        for i in 0..<customCurvePoints.count-1 {
            indices.append(Int32(i))
            indices.append(Int32(i+1))
        }
        
        let source = SCNGeometrySource(vertices: customCurvePoints)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geo = SCNGeometry(sources: [source], elements: [element])
        geo.firstMaterial?.diffuse.contents = NSColor.yellow
        geo.firstMaterial?.emission.contents = NSColor.yellow
        geo.firstMaterial?.readsFromDepthBuffer = false
        
        let node = SCNNode(geometry: geo)
        node.name = name
        node.renderingOrder = 5000
        root.addChildNode(node)
    }
    
    // MARK: - SMILE TEMPLATE
    private func updateSmileTemplate(root: SCNNode) {
        let name = "SMILE_TEMPLATE"
        // Use ID to force rebuild if library changes
        let currentID = libraryID.uuidString
        let nodeName = "\(name)|\(currentID)"
        
        var templateNode = root.childNode(withName: nodeName, recursively: false)
        
        // Remove any old version
        root.childNodes.forEach { if $0.name?.starts(with: name) == true && $0.name != nodeName { $0.removeFromParentNode() } }
        
        if showSmileTemplate {
            if templateNode == nil {
                templateNode = createProceduralArch()
                templateNode?.name = nodeName
                root.addChildNode(templateNode!)
            }
            
            // DECISION: Custom Curve vs Procedural
            if !customCurvePoints.isEmpty && customCurvePoints.count > 5 {
                // Fit teeth to drawn curve
                fitTeethToCustomCurve(templateNode!)
            } else {
                // Standard Procedural Positioning
                applyProceduralTransforms(to: templateNode!)
            }
        } else {
            templateNode?.removeFromParentNode()
        }
    }
    
    // ALGORITHM: Fit Teeth to Drawn Curve
    private func fitTeethToCustomCurve(_ templateNode: SCNNode) {
        // 1. Calculate Curve Length
        var curveLength: CGFloat = 0
        var distances: [CGFloat] = [0]
        for i in 0..<customCurvePoints.count-1 {
            let p1 = customCurvePoints[i]
            let p2 = customCurvePoints[i+1]
            let dist = CGFloat(sqrt(pow(p2.x-p1.x, 2) + pow(p2.y-p1.y, 2) + pow(p2.z-p1.z, 2)))
            curveLength += dist
            distances.append(curveLength)
        }
        
        // 2. Calculate Total Width of Active Teeth (in local units)
        // Assume default width ~0.0085 per tooth if scaling is 1.0
        // We need to sum actual scaled widths.
        // Or simpler: Standard dental ratio sum is approx 45-50mm.
        // Let's assume the unscaled width of 6 teeth is ~0.045m
        let standardArchWidth: CGFloat = 0.045
        
        // 3. Shrink/Stretch Factor
        let scaleToFit = curveLength / standardArchWidth
        
        // 4. Place Teeth
        // Order: Right Canine -> Left Canine (or vice versa depending on drawing direction)
        // Let's assume drawing is Left to Right (screen X increasing)
        // Sort points by X just in case? No, preserve drawing order.
        
        let teethOrder = ["T_3_L", "T_2_L", "T_1_L", "T_1_R", "T_2_R", "T_3_R"]
        // Verify drawing direction: compare first and last point X
        let isLeftToRight = (customCurvePoints.first?.x ?? 0) < (customCurvePoints.last?.x ?? 0)
        let placedTeeth = isLeftToRight ? teethOrder : teethOrder.reversed()
        
        // Distribute equidistant centers (simplified for "stationed")
        // Ideally we use individual widths. For now, uniform spacing.
        let step = curveLength / CGFloat(placedTeeth.count)
        
        for (i, toothName) in placedTeeth.enumerated() {
            guard let tooth = templateNode.childNode(withName: toothName, recursively: true) else { continue }
            
            // Distance along curve
            let d = (CGFloat(i) * step) + (step / 2.0)
            
            // Interpolate Position
            if let (pos, tangent) = interpolateCurve(distance: d, totalLength: curveLength, distances: distances) {
                // Apply Transform
                tooth.position = pos
                
                // Rotation: Look at tangent (Y-up, Z-forward assumption)
                // Dental standard: Z is OUT (Labial), Y is UP (Apical).
                // Tangent is left-right. Normal is out.
                // SCNNode lookAt aligns -Z axis.
                // We want tooth Front to face Out (Normal).
                // Normal = Tangent x Up(0,1,0).
                
                let up = SCNVector3(0, 1, 0)
                let normal = SCNVector3(
                    tangent.y * up.z - tangent.z * up.y,
                    tangent.z * up.x - tangent.x * up.z,
                    tangent.x * up.y - tangent.y * up.x
                )
                
                // Manual Orientation Matrix
                // We want tooth's Z axis to align with 'normal'
                // and X axis to align with 'tangent'
                
                tooth.look(at: SCNVector3(pos.x + normal.x, pos.y + normal.y, pos.z + normal.z),
                           up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
                
                // Apply State Rotation/Scale on top
                let state = toothStates[toothName] ?? ToothState()
                
                // Add local offsets
                tooth.localTranslate(position: SCNVector3(
                    CGFloat(state.positionOffset.x) * 0.01,
                    CGFloat(state.positionOffset.y) * 0.01,
                    CGFloat(state.positionOffset.z) * 0.01
                ))
                
                // Apply User Rotations (Euler)
                tooth.eulerAngles.x += CGFloat(state.rotation.x)
                tooth.eulerAngles.y += CGFloat(state.rotation.y)
                tooth.eulerAngles.z += CGFloat(state.rotation.z)
                
                // Apply "Shrunk to Fit" Scale * User Scale
                let finalScale = scaleToFit * CGFloat(smileParams.scale) // Use global scale slider too
                tooth.scale = SCNVector3(
                    finalScale * CGFloat(state.scale.x),
                    finalScale * CGFloat(state.scale.y),
                    finalScale * CGFloat(state.scale.z)
                )
            }
        }
    }
    
    private func interpolateCurve(distance: CGFloat, totalLength: CGFloat, distances: [CGFloat]) -> (SCNVector3, SCNVector3)? {
        guard !distances.isEmpty else { return nil }
        
        // Find segment
        for i in 0..<distances.count-1 {
            if distance >= distances[i] && distance <= distances[i+1] {
                let start = distances[i]
                let end = distances[i+1]
                let segmentLen = end - start
                if segmentLen == 0 { return (customCurvePoints[i], SCNVector3(1,0,0)) }
                
                let t = (distance - start) / segmentLen // 0..1 in segment
                
                let p1 = customCurvePoints[i]
                let p2 = customCurvePoints[i+1]
                
                // Pos
                let pos = SCNVector3(
                    CGFloat(p1.x) + CGFloat(p2.x - p1.x) * t,
                    CGFloat(p1.y) + CGFloat(p2.y - p1.y) * t,
                    CGFloat(p1.z) + CGFloat(p2.z - p1.z) * t
                )
                
                // Tangent (Direction)
                let dx = CGFloat(p2.x - p1.x)
                let dy = CGFloat(p2.y - p1.y)
                let dz = CGFloat(p2.z - p1.z)
                let len = sqrt(dx*dx + dy*dy + dz*dz)
                let tan = SCNVector3(dx/len, dy/len, dz/len)
                
                return (pos, tan)
            }
        }
        return nil
    }
    
    private func applyProceduralTransforms(to templateNode: SCNNode) {
        var basePos = SCNVector3Zero
        if let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] {
            let cx = (lC.x + rC.x) / 2; let cy = (lC.y + rC.y) / 2; let cz = (lC.z + rC.z) / 2; basePos = SCNVector3(x: cx, y: cy, z: cz)
            if let lipZ = landmarks[.upperLipCenter]?.z { basePos.z = lipZ + 0.005 } else { basePos.z += 0.02 }
            if let mid = landmarks[.midline] { basePos.x = mid.x }
            if let lip = landmarks[.upperLipCenter] { basePos.y = lip.y - 0.002 }
            let dx = rC.x - lC.x; let dy = rC.y - lC.y; let dist = sqrt(dx*dx + dy*dy)
            let baseScale = CGFloat(dist) * 15.0 * CGFloat(smileParams.scale)
            templateNode.scale = SCNVector3(x: baseScale, y: baseScale, z: baseScale)
        }
        
        let px = CGFloat(basePos.x) + CGFloat(smileParams.posX) * 0.05
        let py = CGFloat(basePos.y) + CGFloat(smileParams.posY) * 0.05
        let pz = CGFloat(basePos.z) + CGFloat(smileParams.posZ) * 0.05
        templateNode.position = SCNVector3(x: px, y: py, z: pz)
        
        if let lp = landmarks[.leftPupil], let rp = landmarks[.rightPupil] {
            let dy = rp.y - lp.y; let dx = rp.x - lp.x; let angle = atan2(dy, dx); templateNode.eulerAngles.z = CGFloat(angle)
        }
        
        templateNode.childNodes.forEach { tooth in
            guard let toothName = tooth.name else { return }
            let xVal = CGFloat(tooth.position.x)
            let curveZ = pow(xVal * 5.0, 2) * CGFloat(smileParams.curve) * 0.5
            let state = toothStates[toothName] ?? ToothState()
            
            let tX = xVal + CGFloat(state.positionOffset.x) * 0.01
            let tY = 0.0 + CGFloat(state.positionOffset.y) * 0.01
            let tZ = curveZ + CGFloat(state.positionOffset.z) * 0.01
            
            tooth.position = SCNVector3(x: tX, y: tY, z: tZ)
            tooth.eulerAngles = SCNVector3(x: CGFloat(state.rotation.x), y: CGFloat(state.rotation.y), z: CGFloat(state.rotation.z))
            
            let sRatio = CGFloat(smileParams.ratio) * CGFloat(state.scale.x)
            let sLength = CGFloat(smileParams.length) * CGFloat(state.scale.y)
            let sThick = CGFloat(state.scale.z)
            tooth.scale = SCNVector3(x: sRatio, y: sLength, z: sThick)
            
            tooth.geometry?.firstMaterial?.readsFromDepthBuffer = false
            tooth.renderingOrder = 2000
            if tooth.geometry?.firstMaterial?.emission.contents as? NSColor != NSColor.blue { tooth.geometry?.firstMaterial?.emission.contents = NSColor.black }
        }
    }
    
    // ... [createProceduralArch, loadToothMesh, createToothGeo, drawEstheticAnalysis, updateLandmarkVisuals, updateGrid unchanged from previous robust version]
    private func createProceduralArch() -> SCNNode {
        let root = SCNNode(); let baseW: CGFloat = 0.0085
        let definitions: [(id: Int, wRatio: CGFloat, hRatio: CGFloat, type: String)] = [(1, 1.0, 1.0, "Central"), (2, 0.75, 0.85, "Lateral"), (3, 0.85, 0.95, "Canine")]
        var xCursor: CGFloat = baseW / 2.0
        for def in definitions {
            let w = baseW * def.wRatio; let h = baseW * 1.2 * def.hRatio
            let rNode: SCNNode; let lNode: SCNNode
            if let libURL = toothLibrary[def.type], let libNode = loadToothMesh(url: libURL) {
                rNode = libNode.clone(); lNode = libNode.clone(); lNode.scale.x *= -1
            } else {
                rNode = createToothGeo(width: w, height: h); lNode = createToothGeo(width: w, height: h)
            }
            rNode.position = SCNVector3(x: xCursor, y: 0, z: 0); rNode.name = "T_\(def.id)_R"
            lNode.position = SCNVector3(x: -xCursor, y: 0, z: 0); lNode.name = "T_\(def.id)_L"
            root.addChildNode(rNode); root.addChildNode(lNode)
            xCursor += w
        }
        // Don't apply transforms here, done in updateSmileTemplate
        return root
    }
    
    private func loadToothMesh(url: URL) -> SCNNode? {
        let authorized = url.startAccessingSecurityScopedResource()
        defer { if authorized { url.stopAccessingSecurityScopedResource() } }
        guard let scene = try? SCNScene(url: url, options: nil), let geoNode = findFirstGeometryNode(in: scene.rootNode) else { return nil }
        return MeshUtils.normalize(geoNode)
    }
    
    private func createToothGeo(width: CGFloat, height: CGFloat) -> SCNNode {
        let path = NSBezierPath(roundedRect: CGRect(x: -width/2, y: -height/2, width: width, height: height), xRadius: width*0.3, yRadius: width*0.3)
        let shape = SCNShape(path: path, extrusionDepth: width*0.2); shape.chamferRadius = width*0.05
        let mat = SCNMaterial(); mat.diffuse.contents = NSColor(white: 1.0, alpha: 0.8)
        return SCNNode(geometry: shape)
    }
    private func drawEstheticAnalysis(root: SCNNode) { let containerName = "ESTHETIC_LINES"; root.childNode(withName: containerName, recursively: false)?.removeFromParentNode(); let container = SCNNode(); container.name = containerName; root.addChildNode(container); var safeZ: CGFloat = 0.05; let protrusions = [landmarks[.subnasale], landmarks[.upperLipCenter], landmarks[.lowerLipCenter], landmarks[.menton]]; if let maxZ = protrusions.compactMap({ $0?.z }).max() { safeZ = CGFloat(maxZ) + 0.015 } else if let c1 = landmarks[.leftCanine]?.z, let c2 = landmarks[.rightCanine]?.z { safeZ = CGFloat(max(c1, c2)) + 0.03 }; func drawLine(_ start: SCNVector3, _ end: SCNVector3, color: NSColor) { let p1 = SCNVector3(x: CGFloat(start.x), y: CGFloat(start.y), z: safeZ); let p2 = SCNVector3(x: CGFloat(end.x), y: CGFloat(end.y), z: safeZ); let indices: [Int32] = [0, 1]; let source = SCNGeometrySource(vertices: [p1, p2]); let element = SCNGeometryElement(indices: indices, primitiveType: .line); let geo = SCNGeometry(sources: [source], elements: [element]); geo.firstMaterial?.diffuse.contents = color; geo.firstMaterial?.emission.contents = color; geo.firstMaterial?.readsFromDepthBuffer = false; geo.firstMaterial?.writesToDepthBuffer = false; let node = SCNNode(geometry: geo); node.renderingOrder = 1000; container.addChildNode(node) }; if let lp = landmarks[.leftPupil], let rp = landmarks[.rightPupil] { drawLine(lp, rp, color: .yellow); let mid = SCNVector3(x: (lp.x+rp.x)/2, y: (lp.y+rp.y)/2, z: 0); let drop = SCNVector3(x: mid.x, y: mid.y - 0.20, z: 0); drawLine(mid, drop, color: .cyan) }; if let gl = landmarks[.glabella], let sn = landmarks[.subnasale], let me = landmarks[.menton] { let w: CGFloat = 0.06; drawLine(SCNVector3(x: gl.x-w, y: gl.y, z: 0), SCNVector3(x: gl.x+w, y: gl.y, z: 0), color: .white); drawLine(SCNVector3(x: sn.x-w, y: sn.y, z: 0), SCNVector3(x: sn.x+w, y: sn.y, z: 0), color: .white); drawLine(SCNVector3(x: me.x-w, y: me.y, z: 0), SCNVector3(x: me.x+w, y: me.y, z: 0), color: .white) }; if let mid = landmarks[.midline], let lC = landmarks[.leftCanine], let rC = landmarks[.rightCanine] { let dx = rC.x - lC.x; let dy = rC.y - lC.y; let archWidth = CGFloat(sqrt(dx*dx + dy*dy)); let yTop = mid.y + 0.005; let yBot = mid.y - 0.010; let wCent = archWidth * 0.23; let wLatCumulative = archWidth * 0.38; let wCanCumulative = archWidth * 0.50; drawLine(SCNVector3(x: CGFloat(mid.x), y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x), y: CGFloat(yBot), z: 0), color: .red); drawLine(SCNVector3(x: CGFloat(mid.x)+wCent, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)+wCent, y: CGFloat(yBot), z: 0), color: .red); drawLine(SCNVector3(x: CGFloat(mid.x)-wCent, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)-wCent, y: CGFloat(yBot), z: 0), color: .red); drawLine(SCNVector3(x: CGFloat(mid.x)+wLatCumulative, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)+wLatCumulative, y: CGFloat(yBot), z: 0), color: .blue); drawLine(SCNVector3(x: CGFloat(mid.x)-wLatCumulative, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)-wLatCumulative, y: CGFloat(yBot), z: 0), color: .blue); drawLine(SCNVector3(x: CGFloat(mid.x)+wCanCumulative, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)+wCanCumulative, y: CGFloat(yBot), z: 0), color: .green); drawLine(SCNVector3(x: CGFloat(mid.x)-wCanCumulative, y: CGFloat(yTop), z: 0), SCNVector3(x: CGFloat(mid.x)-wCanCumulative, y: CGFloat(yBot), z: 0), color: .green) }; if let sn = landmarks[.subnasale], let me = landmarks[.menton], let st = landmarks[.upperLipCenter] { drawLine(sn, me, color: .gray); let w: CGFloat = 0.03; drawLine(SCNVector3(x: CGFloat(st.x) - w, y: CGFloat(st.y), z: 0), SCNVector3(x: CGFloat(st.x) + w, y: CGFloat(st.y), z: 0), color: .magenta) } }
    private func updateLandmarkVisuals(root: SCNNode) { let containerName = "LANDMARKS_CONTAINER"; root.childNode(withName: containerName, recursively: false)?.removeFromParentNode(); let container = SCNNode(); container.name = containerName; root.addChildNode(container); for (type, pos) in landmarks { let sphere = SCNSphere(radius: 0.0015); var color: NSColor = .blue; switch type { case .rightPupil, .leftPupil: color = .yellow; case .midline, .glabella: color = .cyan; case .rightCommissure, .leftCommissure: color = .green; case .subnasale, .menton: color = .white; default: color = .blue }; sphere.firstMaterial?.diffuse.contents = color; sphere.firstMaterial?.emission.contents = color; sphere.firstMaterial?.readsFromDepthBuffer = false; let node = SCNNode(geometry: sphere); node.position = pos; node.renderingOrder = 1001; container.addChildNode(node) } }
    private func updateGrid(root: SCNNode) { let name = "GOLDEN_GRID"; var gridNode = root.childNode(withName: name, recursively: false); if showGrid { if gridNode == nil { let grid = SCNNode(); let mat = SCNMaterial(); mat.diffuse.contents = NSColor.cyan; let lineH = SCNPlane(width: 0.0005, height: 0.1); lineH.materials = [mat]; let cW: CGFloat = 0.0085; let lW = cW * 0.618; let offsets = [0, cW, cW + lW]; for x in offsets { let rL = SCNNode(geometry: lineH); rL.position.x = x; grid.addChildNode(rL); let lL = SCNNode(geometry: lineH); lL.position.x = -x; grid.addChildNode(lL) }; grid.name = name; root.addChildNode(grid); gridNode = grid }; gridNode?.position = root.childNode(withName: "SMILE_TEMPLATE", recursively: false)?.position ?? SCNVector3Zero; gridNode?.position.z += 0.005 } else { gridNode?.removeFromParentNode() } }
}
