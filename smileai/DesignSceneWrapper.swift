import SwiftUI
import SceneKit

// Params struct to pass data easily
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
    
    // Crop Mode
    let isCleanupMode: Bool
    let cropBox: (min: SCNVector3, max: SCNVector3)
    
    // Smile Design Mode
    var showSmileTemplate: Bool = false
    var smileParams: SmileTemplateParams = SmileTemplateParams(posX: 0, posY: 0, posZ: 0, scale: 1, curve: 0, length: 1, ratio: 0.8)
    var showGrid: Bool = false
    
    // Callbacks
    var onModelLoaded: ((_ bounds: (min: SCNVector3, max: SCNVector3)) -> Void)?
    
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor.black
        view.scene = SCNScene()
        return view
    }
    
    func updateNSView(_ uiView: SCNView, context: Context) {
        guard let root = uiView.scene?.rootNode else { return }
        let patientNodeName = "PATIENT_MODEL"
        
        // 1. Load Model (Lazy Load)
        if root.childNode(withName: patientNodeName, recursively: false) == nil {
            if let node = try? SCNScene(url: scanURL, options: nil).rootNode.childNodes.first {
                node.name = patientNodeName
                
                // Center Pivot
                let (min, max) = node.boundingBox
                node.pivot = SCNMatrix4MakeTranslation((min.x+max.x)/2, (min.y+max.y)/2, (min.z+max.z)/2)
                node.position = SCNVector3Zero
                node.geometry?.firstMaterial?.isDoubleSided = true
                
                root.addChildNode(node)
                
                DispatchQueue.main.async {
                    // Send bounds back to UI to auto-set slider ranges
                    let w = CGFloat(max.x - min.x); let h = CGFloat(max.y - min.y); let d = CGFloat(max.z - min.z)
                    let pad = w * 0.1
                    self.onModelLoaded?((
                        min: SCNVector3(-w/2 - pad, -h/2 - pad, -d/2 - pad),
                        max: SCNVector3(w/2 + pad, h/2 + pad, d/2 + pad)
                    ))
                    uiView.defaultCameraController.frameNodes([node])
                }
            }
        }
        
        // 2. Handle Crop Tool
        updateCropTool(root: root)
        
        // 3. Handle Smile Template
        updateSmileTemplate(root: root)
        
        // 4. Handle Grid
        updateGrid(root: root)
    }
    
    // MARK: - Crop Logic
    
    private func updateCropTool(root: SCNNode) {
        let patientNode = root.childNode(withName: "PATIENT_MODEL", recursively: false)
        let boxName = "CROP_BOX"
        
        if isCleanupMode {
            // Apply Shader
            let shader = """
            #pragma transparent
            #pragma body
            float3 p = _surface.position;
            if (p.x < custom_minX || p.x > custom_maxX ||
                p.y < custom_minY || p.y > custom_maxY ||
                p.z < custom_minZ || p.z > custom_maxZ) {
                discard_fragment();
            }
            """
            if patientNode?.geometry?.shaderModifiers == nil {
                patientNode?.geometry?.shaderModifiers = [.surface: shader]
            }
            
            if let mat = patientNode?.geometry?.firstMaterial {
                // SCNVector3 components are CGFloat on macOS, convert to Float for Shader
                mat.setValue(Float(cropBox.min.x), forKey: "custom_minX"); mat.setValue(Float(cropBox.max.x), forKey: "custom_maxX")
                mat.setValue(Float(cropBox.min.y), forKey: "custom_minY"); mat.setValue(Float(cropBox.max.y), forKey: "custom_maxY")
                mat.setValue(Float(cropBox.min.z), forKey: "custom_minZ"); mat.setValue(Float(cropBox.max.z), forKey: "custom_maxZ")
            }
            
            // Draw Box
            var boxNode = root.childNode(withName: boxName, recursively: false)
            if boxNode == nil {
                let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
                box.firstMaterial?.diffuse.contents = NSColor.yellow
                box.firstMaterial?.fillMode = .lines
                let node = SCNNode(geometry: box)
                node.name = boxName
                root.addChildNode(node)
                boxNode = node
            }
            
            let w = CGFloat(cropBox.max.x - cropBox.min.x)
            let h = CGFloat(cropBox.max.y - cropBox.min.y)
            let l = CGFloat(cropBox.max.z - cropBox.min.z)
            if let geo = boxNode?.geometry as? SCNBox { geo.width = w; geo.height = h; geo.length = l }
            boxNode?.position = SCNVector3((cropBox.min.x + cropBox.max.x)/2, (cropBox.min.y + cropBox.max.y)/2, (cropBox.min.z + cropBox.max.z)/2)
            
        } else {
            patientNode?.geometry?.shaderModifiers = nil
            root.childNode(withName: boxName, recursively: false)?.removeFromParentNode()
        }
    }
    
    // MARK: - Smile Template Logic
    
    private func updateSmileTemplate(root: SCNNode) {
        let name = "SMILE_TEMPLATE"
        var templateNode = root.childNode(withName: name, recursively: false)
        
        if showSmileTemplate {
            if templateNode == nil {
                templateNode = createProceduralArch()
                templateNode?.name = name
                root.addChildNode(templateNode!)
            }
            
            // Apply User Params (Cast Float -> CGFloat for macOS)
            // 1. Position
            templateNode?.position = SCNVector3(CGFloat(smileParams.posX), CGFloat(smileParams.posY), CGFloat(smileParams.posZ))
            
            // 2. Global Scale (Arch Width)
            let s = CGFloat(smileParams.scale)
            templateNode?.scale = SCNVector3(s, s, s)
            
            // 3. Morph Shape (Curve & Length)
            templateNode?.childNodes.forEach { tooth in
                // Adjust geometry scale for length/ratio
                // Scale Y = Length, Scale X = Ratio (Width)
                tooth.scale = SCNVector3(CGFloat(smileParams.ratio), CGFloat(smileParams.length), 1.0)
                
                // Adjust Arch Curve
                // Parabolic curve: Z = x^2 * curveFactor
                // We use the tooth's initial X position to calculate Z offset
                let xVal = Float(tooth.position.x)
                let zOffset = pow(xVal * 5.0, 2) * smileParams.curve * 0.1
                tooth.position.z = CGFloat(zOffset)
            }
            
        } else {
            templateNode?.removeFromParentNode()
        }
    }
    
    private func createProceduralArch() -> SCNNode {
        let root = SCNNode()
        
        // Standard width reference in meters
        let baseW: Float = 0.0085 // 8.5mm central width
        
        // 6 Anterior teeth (3 Left, 3 Right)
        let definitions: [(id: Int, wRatio: Float, hRatio: Float)] = [
            (1, 1.0, 1.0),    // Central
            (2, 0.75, 0.85),  // Lateral
            (3, 0.85, 0.95)   // Canine
        ]
        
        var xCursor: Float = baseW / 2.0 // Start half a tooth width from center
        
        for def in definitions {
            let w = baseW * def.wRatio
            let h = baseW * 1.2 * def.hRatio
            
            // Create Right Tooth (+)
            let rNode = createToothGeo(width: CGFloat(w), height: CGFloat(h))
            rNode.position = SCNVector3(CGFloat(xCursor), 0, 0)
            rNode.name = "T_\(def.id)_R"
            root.addChildNode(rNode)
            
            // Create Left Tooth (-)
            let lNode = createToothGeo(width: CGFloat(w), height: CGFloat(h))
            lNode.position = SCNVector3(CGFloat(-xCursor), 0, 0)
            lNode.name = "T_\(def.id)_L"
            root.addChildNode(lNode)
            
            xCursor += w // Move cursor
        }
        
        return root
    }
    
    private func createToothGeo(width: CGFloat, height: CGFloat) -> SCNNode {
        // macOS: Use NSBezierPath instead of UIBezierPath
        let rect = CGRect(x: -width/2, y: -height/2, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: width * 0.3, yRadius: width * 0.3)
        
        let shape = SCNShape(path: path, extrusionDepth: 0.002) // 2mm thick
        shape.chamferRadius = width * 0.05
        
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(white: 1.0, alpha: 0.8)
        mat.lightingModel = .physicallyBased
        mat.metalness.contents = 0.1
        mat.roughness.contents = 0.3
        shape.materials = [mat]
        
        return SCNNode(geometry: shape)
    }
    
    // MARK: - Grid Logic
    
    private func updateGrid(root: SCNNode) {
        let name = "GOLDEN_GRID"
        var gridNode = root.childNode(withName: name, recursively: false)
        
        if showGrid {
            if gridNode == nil {
                // Golden Ratio Lines
                let grid = SCNNode()
                let mat = SCNMaterial(); mat.diffuse.contents = NSColor.cyan
                
                let lineH = SCNPlane(width: 0.0005, height: 0.1)
                lineH.materials = [mat]
                
                let cW: CGFloat = 0.0085
                let lW = cW * 0.618
                
                let offsets: [CGFloat] = [0, cW, cW + lW]
                
                for x in offsets {
                    let rL = SCNNode(geometry: lineH); rL.position.x = x
                    let lL = SCNNode(geometry: lineH); lL.position.x = -x
                    grid.addChildNode(rL)
                    grid.addChildNode(lL)
                }
                
                let lineW = SCNPlane(width: 0.1, height: 0.0005)
                lineW.materials = [mat]
                let hNode = SCNNode(geometry: lineW)
                hNode.position.y = -cW/2
                grid.addChildNode(hNode)
                
                grid.name = name
                root.addChildNode(grid)
                gridNode = grid
            }
            
            // Cast params to CGFloat for macOS
            gridNode?.position = SCNVector3(
                CGFloat(smileParams.posX),
                CGFloat(smileParams.posY),
                CGFloat(smileParams.posZ) + 0.005
            )
        } else {
            gridNode?.removeFromParentNode()
        }
    }
}
