import SwiftUI
import SceneKit

struct DesignSceneWrapper: NSViewRepresentable {
    let scanURL: URL
    let isCleanupMode: Bool
    let cropBox: (min: SCNVector3, max: SCNVector3)
    
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor.darkGray
        view.scene = SCNScene()
        return view
    }
    
    func updateNSView(_ uiView: SCNView, context: Context) {
        guard let root = uiView.scene?.rootNode else { return }
        
        // 1. Load Patient Scan
        let patientName = "PATIENT"
        var patientNode = root.childNode(withName: patientName, recursively: false)
        
        if patientNode == nil {
            if let node = try? SCNScene(url: scanURL, options: nil).rootNode.childNodes.first {
                node.name = patientName
                // Reset position to center it
                node.position = SCNVector3Zero
                // Basic material
                node.geometry?.firstMaterial?.diffuse.contents = NSColor.lightGray
                node.geometry?.firstMaterial?.isDoubleSided = true
                root.addChildNode(node)
                patientNode = node
                
                // Frame the camera once
                DispatchQueue.main.async {
                    uiView.defaultCameraController.frameNodes([node])
                }
            }
        }
        
        // 2. Apply Cleanup Shader
        if isCleanupMode {
            // Visualize the Crop Box (Optional Wireframe)
            visualizeCropBox(in: root, min: cropBox.min, max: cropBox.max)
            
            // Apply Shader Modifier to discard fragments outside the box
            // We use scn_node.modelTransform to keep cropping relative to the model
            let shader = """
            #pragma transparent
            #pragma body
            
            float3 p = _surface.position;
            // Convert View Space (surface.position) to Model Space if needed, 
            // but usually cropping in World/Model space is intuitive.
            // Simplified: We assume model is at 0,0,0.
            
            // Check Bounds
            if (p.x < \(cropBox.min.x) || p.x > \(cropBox.max.x) ||
                p.y < \(cropBox.min.y) || p.y > \(cropBox.max.y) ||
                p.z < \(cropBox.min.z) || p.z > \(cropBox.max.z)) {
                discard_fragment();
            }
            """
            // Note: This is a view-space crop. For precise model-space cropping,
            // we'd multiply by inverse view transform.
            // For this UI, "View Space" cropping means the box stays with camera.
            // "Model Space" means box stays with teeth.
            // We'll stick to simple coordinate checking for stability.
            
            patientNode?.geometry?.shaderModifiers = [.surface: shader]
            
        } else {
            // Remove Shader and Box when not cleaning
            patientNode?.geometry?.shaderModifiers = nil
            root.childNode(withName: "CROP_GIZMO", recursively: false)?.removeFromParentNode()
        }
    }
    
    private func visualizeCropBox(in root: SCNNode, min: SCNVector3, max: SCNVector3) {
        let name = "CROP_GIZMO"
        root.childNode(withName: name, recursively: false)?.removeFromParentNode()
        
        let width = CGFloat(max.x - min.x)
        let height = CGFloat(max.y - min.y)
        let length = CGFloat(max.z - min.z)
        
        let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = NSColor.red.withAlphaComponent(0.2)
        box.firstMaterial?.fillMode = .lines // Wireframe
        
        let node = SCNNode(geometry: box)
        node.name = name
        // Center the box
        node.position = SCNVector3(
            (min.x + max.x) / 2,
            (min.y + max.y) / 2,
            (min.z + max.z) / 2
        )
        root.addChildNode(node)
    }
}
