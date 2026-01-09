import SceneKit

class FreeRotateGizmo: SCNNode {
    
    init(boundMin: SCNVector3, boundMax: SCNVector3) {
        super.init()
        self.name = "MANIPULATION_GIZMO"
        
        let width = CGFloat(boundMax.x - boundMin.x)
        let height = CGFloat(boundMax.y - boundMin.y)
        let length = CGFloat(boundMax.z - boundMin.z)
        let maxDim = max(width, max(height, length))
        
        // 1. Wireframe Box (Visual Boundary)
        let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0)
        let boxNode = SCNNode(geometry: box)
        box.firstMaterial?.diffuse.contents = NSColor.cyan
        box.firstMaterial?.fillMode = .lines // Wireframe
        box.firstMaterial?.emission.contents = NSColor.cyan
        self.addChildNode(boxNode)
        
        // 2. Transparent Sphere (The Rotation Handle)
        let sphere = SCNSphere(radius: maxDim * 0.8)
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.name = "GIZMO_ROTATE_HANDLE" // ID for Hit Test
        sphereNode.opacity = 0.2
        sphere.firstMaterial?.diffuse.contents = NSColor.yellow
        sphere.firstMaterial?.transparency = 0.3
        sphere.firstMaterial?.readsFromDepthBuffer = false // Always visible
        self.addChildNode(sphereNode)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
