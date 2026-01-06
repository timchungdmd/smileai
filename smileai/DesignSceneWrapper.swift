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
    let isCleanupMode: Bool
    @Binding var triggerDelete: Bool
    var onDelete: ((Set<Int>) -> Void)?
    
    var showSmileTemplate: Bool
    var smileParams: SmileTemplateParams
    var showGrid: Bool
    
    var onModelLoaded: ((_ bounds: (min: SCNVector3, max: SCNVector3)) -> Void)?
    
    func makeNSView(context: Context) -> EditorView {
        let view = EditorView()
        // OrbitArcball = "Holding object in hand" rotation
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
        view.allowsCameraControl = !isCleanupMode
        view.isPaintMode = isCleanupMode
        
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
        
        if root.childNodes.isEmpty {
            if let scene = try? SCNScene(url: scanURL, options: nil),
               let geoNode = findFirstGeometryNode(in: scene.rootNode) {
                
                let node = geoNode.clone()
                node.name = "PATIENT_MODEL"
                
                // --- FIX 1: True Geometric Centering ---
                // Calculate bounds of the GEOMETRY (skips empty node transforms)
                if let geo = node.geometry {
                    let (min, max) = geo.boundingBox
                    let cx = (min.x + max.x) / 2
                    let cy = (min.y + max.y) / 2
                    let cz = (min.z + max.z) / 2
                    node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
                }
                node.position = SCNVector3Zero
                
                // --- FIX 2: Prevent Crashes & White Overlay ---
                if let geo = node.geometry {
                    // Generate Tangents if missing
                    if geo.sources(for: .tangent).isEmpty {
                        let mdlMesh = MDLMesh(scnGeometry: geo)
                        mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
                        let newGeo = SCNGeometry(mdlMesh: mdlMesh)
                        newGeo.materials = geo.materials
                        node.geometry = newGeo
                    }
                    
                    // Material Setup
                    node.geometry?.materials.forEach { mat in
                        mat.lightingModel = .physicallyBased
                        mat.isDoubleSided = true
                        mat.roughness.contents = 0.5 // Less shiny = less white glare
                        mat.metalness.contents = 0.0
                        
                        // Fallback Color: If texture is missing, use "Dental Clay" color
                        // instead of White. (Red: 0.9, Green: 0.8, Blue: 0.7)
                        if mat.diffuse.contents == nil {
                            mat.diffuse.contents = NSColor(calibratedRed: 0.9, green: 0.85, blue: 0.8, alpha: 1.0)
                        }
                    }
                }
                
                root.addChildNode(node)
                view.prepareForPainting(node: node)
                
                DispatchQueue.main.async {
                    self.onModelLoaded?((min: node.boundingBox.min, max: node.boundingBox.max))
                    // Force camera to center
                    view.defaultCameraController.target = SCNVector3Zero
                    view.defaultCameraController.frameNodes([node])
                }
            }
        }
        
        updateSmileTemplate(root: root, patientNode: root.childNode(withName: "PATIENT_MODEL", recursively: true))
        updateGrid(root: root)
    }
    
    private func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findFirstGeometryNode(in: child) { return found }
        }
        return nil
    }
    
    // (Keep updateSmileTemplate, createProceduralArch, createToothGeo, updateGrid same as before...)
    // ...
    // MARK: - Smile Template Logic
    private func updateSmileTemplate(root: SCNNode, patientNode: SCNNode?) {
        let name = "SMILE_TEMPLATE"
        var templateNode = root.childNode(withName: name, recursively: false)
        
        if showSmileTemplate {
            if templateNode == nil {
                templateNode = createProceduralArch()
                templateNode?.name = name
                root.addChildNode(templateNode!)
            }
            
            // Auto-Scale
            var unitScale: CGFloat = 1.0
            if let pNode = patientNode {
                let (min, max) = pNode.boundingBox
                if (max.x - min.x) > 10 { unitScale = 1000.0 }
            }
            
            let moveScale = unitScale * 0.5
            templateNode?.position = SCNVector3(
                CGFloat(smileParams.posX) * moveScale,
                CGFloat(smileParams.posY) * moveScale,
                CGFloat(smileParams.posZ) * moveScale
            )
            let s = CGFloat(smileParams.scale) * unitScale
            templateNode?.scale = SCNVector3(s, s, s)
            
            templateNode?.childNodes.forEach { tooth in
                tooth.scale = SCNVector3(CGFloat(smileParams.ratio), CGFloat(smileParams.length), 1.0)
                let xVal = Float(tooth.position.x)
                let zOffset = pow(xVal * 5.0, 2) * smileParams.curve * 0.5
                tooth.position.z = CGFloat(zOffset)
            }
        } else {
            templateNode?.removeFromParentNode()
        }
    }
    
    private func createProceduralArch() -> SCNNode {
        let root = SCNNode()
        let baseW: CGFloat = 0.0085
        let definitions: [(id: Int, wRatio: CGFloat, hRatio: CGFloat)] = [
            (1, 1.0, 1.0), (2, 0.75, 0.85), (3, 0.85, 0.95)
        ]
        var xCursor: CGFloat = baseW / 2.0
        for def in definitions {
            let w = baseW * def.wRatio; let h = baseW * 1.2 * def.hRatio
            let rNode = createToothGeo(width: w, height: h)
            rNode.position = SCNVector3(xCursor, 0, 0)
            root.addChildNode(rNode)
            let lNode = createToothGeo(width: w, height: h)
            lNode.position = SCNVector3(-xCursor, 0, 0)
            root.addChildNode(lNode)
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
    
    // MARK: - Grid Logic
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
                let lineW = SCNPlane(width: 0.1, height: 0.0005); lineW.materials = [mat]
                let hNode = SCNNode(geometry: lineW); hNode.position.y = -cW/2; grid.addChildNode(hNode)
                grid.name = name; root.addChildNode(grid); gridNode = grid
            }
            gridNode?.position = SCNVector3(CGFloat(smileParams.posX), CGFloat(smileParams.posY), CGFloat(smileParams.posZ) + 0.005)
        } else {
            gridNode?.removeFromParentNode()
        }
    }
}

// MARK: - Custom Editor View

class EditorView: SCNView {
    var isPaintMode: Bool = false
    private var geometryNode: SCNNode?
    
    struct FloatColor { var r, g, b, a: Float }
    private var vertexColors: [FloatColor] = []
    public var selectedIndices: Set<Int> = []
    
    func prepareForPainting(node: SCNNode) {
        self.geometryNode = node
        guard let geo = node.geometry, let src = geo.sources(for: .vertex).first else { return }
        // Init White (1,1,1,1) so textures show through.
        self.vertexColors = Array(repeating: FloatColor(r: 1, g: 1, b: 1, a: 1), count: src.vectorCount)
        updateColorGeometry()
    }
    
    func clearSelection() {
        selectedIndices.removeAll()
        vertexColors = vertexColors.map { _ in FloatColor(r: 1, g: 1, b: 1, a: 1) }
        updateColorGeometry()
    }
    
    override func mouseDown(with event: NSEvent) {
        if isPaintMode { paint(event: event) } else { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if isPaintMode { paint(event: event) } else { super.mouseDragged(with: event) }
    }
    
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
                    vertexColors[i] = FloatColor(r: 1, g: 0, b: 0, a: 1) // RED
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
