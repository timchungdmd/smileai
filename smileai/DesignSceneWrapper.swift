import SwiftUI
import SceneKit

struct DesignSceneWrapper: NSViewRepresentable {
    let scanURL: URL
    let isCleanupMode: Bool
    let cropBox: (min: SCNVector3, max: SCNVector3)
    
    // Auto-fit callback
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
        
        let name = "PATIENT_MODEL"
        var modelNode = root.childNode(withName: name, recursively: false)
        
        // 1. Load if missing
        if modelNode == nil {
            if let node = try? SCNScene(url: scanURL, options: nil).rootNode.childNodes.first {
                node.name = name
                
                // Reset Pivot to Center
                let (min, max) = node.boundingBox
                node.pivot = SCNMatrix4MakeTranslation((min.x+max.x)/2, (min.y+max.y)/2, (min.z+max.z)/2)
                node.position = SCNVector3Zero
                node.geometry?.firstMaterial?.isDoubleSided = true
                
                root.addChildNode(node)
                modelNode = node
                
                // Calculate Size for UI Sliders
                let w = CGFloat(max.x - min.x)
                let h = CGFloat(max.y - min.y)
                let d = CGFloat(max.z - min.z)
                let pad = w * 0.1
                
                DispatchQueue.main.async {
                    self.onModelLoaded?((
                        min: SCNVector3(-w/2 - pad, -h/2 - pad, -d/2 - pad),
                        max: SCNVector3(w/2 + pad, h/2 + pad, d/2 + pad)
                    ))
                    uiView.defaultCameraController.frameNodes([node])
                }
            }
        }
        
        // 2. Crop Logic
        if isCleanupMode {
            // A. Shader
            // Note: We use the node's local bounding box logic.
            // Since we centered the pivot, local (0,0,0) is the center of the model.
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
            
            if modelNode?.geometry?.shaderModifiers == nil {
                modelNode?.geometry?.shaderModifiers = [.surface: shader]
            }
            
            // B. Update Uniforms (Crucial for Slider Interactivity)
            if let mat = modelNode?.geometry?.firstMaterial {
                mat.setValue(cropBox.min.x, forKey: "custom_minX")
                mat.setValue(cropBox.max.x, forKey: "custom_maxX")
                mat.setValue(cropBox.min.y, forKey: "custom_minY")
                mat.setValue(cropBox.max.y, forKey: "custom_maxY")
                mat.setValue(cropBox.min.z, forKey: "custom_minZ")
                mat.setValue(cropBox.max.z, forKey: "custom_maxZ")
            }
            
            // C. Visual Box
            drawBox(root: root, min: cropBox.min, max: cropBox.max)
            
        } else {
            modelNode?.geometry?.shaderModifiers = nil
            root.childNode(withName: "CROP_BOX", recursively: false)?.removeFromParentNode()
        }
    }
    
    private func drawBox(root: SCNNode, min: SCNVector3, max: SCNVector3) {
        let name = "CROP_BOX"
        var boxNode = root.childNode(withName: name, recursively: false)
        
        if boxNode == nil {
            let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = NSColor.yellow
            box.firstMaterial?.emission.contents = NSColor.yellow
            box.firstMaterial?.fillMode = .lines
            let node = SCNNode(geometry: box)
            node.name = name
            root.addChildNode(node)
            boxNode = node
        }
        
        let w = CGFloat(max.x - min.x)
        let h = CGFloat(max.y - min.y)
        let l = CGFloat(max.z - min.z)
        
        if let geo = boxNode?.geometry as? SCNBox {
            geo.width = w; geo.height = h; geo.length = l
        }
        
        boxNode?.position = SCNVector3((min.x + max.x)/2, (min.y + max.y)/2, (min.z + max.z)/2)
    }
}
