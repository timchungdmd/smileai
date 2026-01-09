import SceneKit
import Combine
import SwiftUI

class SmileCurveEditor: ObservableObject {
    private weak var rootNode: SCNNode?
    
    @Published private(set) var points: [SCNVector3] = []
    private var handleNodes: [SCNNode] = []
    private var lineNode: SCNNode?
    
    var isClosed: Bool = false
    var isLocked: Bool = false { didSet { updateVisuals() } }
    
    var onCurveChanged: (([SCNVector3]) -> Void)?
    
    init() {}
    
    func setup(in root: SCNNode) {
        self.rootNode = root
        refreshNodes()
    }
    
    func setPoints(_ newPoints: [SCNVector3]) {
        if points.count == newPoints.count { return } // Basic diff check
        self.points = newPoints
        refreshNodes()
    }
    
    func getPointIndex(for node: SCNNode) -> Int? {
        guard let name = node.name, name.hasPrefix("CURVE_HANDLE_") else { return nil }
        return Int(name.replacingOccurrences(of: "CURVE_HANDLE_", with: ""))
    }
    
    func handleClick(at worldPos: SCNVector3) {
        guard !isLocked else { return }
        if isClosed { return } // STOP ADDING if closed
        
        points.append(worldPos)
        addHandleNode(at: worldPos, index: points.count - 1)
        updateLineGeometry()
        onCurveChanged?(points)
    }
    
    func updatePoint(index: Int, position: SCNVector3) {
        guard index >= 0 && index < points.count else { return }
        guard !isLocked else { return }
        
        points[index] = position
        if index < handleNodes.count { handleNodes[index].position = position }
        updateLineGeometry()
        onCurveChanged?(points)
    }
    
    func closeLoop() {
        guard !isClosed, points.count >= 3 else { return }
        isClosed = true
        updateVisuals()
        onCurveChanged?(points)
    }
    
    func clear() {
        points.removeAll(); handleNodes.forEach { $0.removeFromParentNode() }; handleNodes.removeAll(); lineNode?.removeFromParentNode(); isClosed = false; onCurveChanged?([])
    }
    
    private func refreshNodes() {
        guard let root = rootNode else { return }
        root.enumerateChildNodes { n, _ in if n.name?.contains("CURVE_") == true { n.removeFromParentNode() } }
        handleNodes.removeAll(); lineNode?.removeFromParentNode()
        for (i, p) in points.enumerated() { addHandleNode(at: p, index: i) }
        updateLineGeometry()
    }
    
    private func addHandleNode(at pos: SCNVector3, index: Int) {
        guard let root = rootNode else { return }
        let sphere = SCNSphere(radius: 0.0025) // Larger dot
        let mat = SCNMaterial(); let color: NSColor = isLocked ? .gray : .orange
        mat.diffuse.contents = color; mat.emission.contents = color
        mat.readsFromDepthBuffer = false // Always visible
        sphere.firstMaterial = mat
        let node = SCNNode(geometry: sphere); node.position = pos; node.name = "CURVE_HANDLE_\(index)"; node.renderingOrder = 6000
        root.addChildNode(node); handleNodes.append(node)
    }
    
    private func updateVisuals() {
        let color: NSColor = isLocked ? .gray : (isClosed ? .green : .orange)
        handleNodes.forEach { $0.geometry?.firstMaterial?.diffuse.contents = color; $0.geometry?.firstMaterial?.emission.contents = color }
        updateLineGeometry()
    }
    
    private func updateLineGeometry() {
        guard let root = rootNode, points.count > 1 else { lineNode?.removeFromParentNode(); return }
        lineNode?.removeFromParentNode()
        var indices: [Int32] = []; for i in 0..<points.count - 1 { indices.append(Int32(i)); indices.append(Int32(i + 1)) }
        if isClosed { indices.append(Int32(points.count - 1)); indices.append(0) }
        let src = SCNGeometrySource(vertices: points); let el = SCNGeometryElement(indices: indices, primitiveType: .line); let geo = SCNGeometry(sources: [src], elements: [el])
        geo.firstMaterial?.diffuse.contents = NSColor.yellow; geo.firstMaterial?.emission.contents = NSColor.yellow; geo.firstMaterial?.readsFromDepthBuffer = false
        let node = SCNNode(geometry: geo); node.name = "CURVE_LINE"; node.renderingOrder = 5999
        root.addChildNode(node); lineNode = node
    }
}
