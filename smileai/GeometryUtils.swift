import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class GeometryUtils {
    
    enum ExportFormat: String, CaseIterable, Identifiable {
        case stl = "stl"
        case obj = "obj"
        case usdz = "usdz"
        var id: String { rawValue }
    }
    
    static func deleteVertices(sourceURL: URL, destinationURL: URL, indicesToDelete: Set<Int>, format: ExportFormat) throws {
        
        // 1. Load Scene
        let scene = try SCNScene(url: sourceURL, options: nil)
        
        // Robust Node Finder
        var targetNode: SCNNode?
        scene.rootNode.enumerateChildNodes { node, stop in
            if node.geometry != nil {
                targetNode = node
                stop.pointee = true
            }
        }
        
        guard let node = targetNode,
              let geo = node.geometry,
              let vertexSource = geo.sources(for: .vertex).first,
              let element = geo.elements.first else {
            throw NSError(domain: "Geo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid geometry or no mesh found."])
        }
        
        // 2. Map Old Indices -> New Indices
        var oldToNewMap = [Int: Int]()
        var keptIndexCount = 0
        
        for i in 0..<vertexSource.vectorCount {
            if indicesToDelete.contains(i) {
                oldToNewMap[i] = -1
            } else {
                oldToNewMap[i] = keptIndexCount
                keptIndexCount += 1
            }
        }
        
        if keptIndexCount == 0 {
            throw NSError(domain: "Geo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Selection would delete the entire mesh."])
        }
        
        // 3. Rebuild Vertex Sources (Compact)
        var newSources: [SCNGeometrySource] = []
        
        for source in geo.sources {
            let srcStride = source.dataStride
            let srcOffset = source.dataOffset
            let componentSize = source.bytesPerComponent * source.componentsPerVector
            
            // Compact Stride
            let dstStride = componentSize
            var newData = Data(count: keptIndexCount * dstStride)
            
            source.data.withUnsafeBytes { srcPtr in
                newData.withUnsafeMutableBytes { dstPtr in
                    var dstIndex = 0
                    for i in 0..<vertexSource.vectorCount {
                        if oldToNewMap[i]! != -1 {
                            let srcLoc = i * srcStride + srcOffset
                            if srcLoc + componentSize <= srcPtr.count {
                                let srcAddress = srcPtr.baseAddress!.advanced(by: srcLoc)
                                let dstAddress = dstPtr.baseAddress!.advanced(by: dstIndex * dstStride)
                                dstAddress.copyMemory(from: srcAddress, byteCount: componentSize)
                            }
                            dstIndex += 1
                        }
                    }
                }
            }
            
            let newSource = SCNGeometrySource(
                data: newData,
                semantic: source.semantic,
                vectorCount: keptIndexCount,
                usesFloatComponents: source.usesFloatComponents,
                componentsPerVector: source.componentsPerVector,
                bytesPerComponent: source.bytesPerComponent,
                dataOffset: 0,
                dataStride: dstStride
            )
            newSources.append(newSource)
        }
        
        // 4. Rebuild Triangles
        var newIndices: [UInt32] = []
        element.data.withUnsafeBytes { buffer in
            let triangleCount = element.primitiveCount
            let is32Bit = element.bytesPerIndex == 4
            for t in 0..<triangleCount {
                let i = t * 3
                let base = i * element.bytesPerIndex
                let idx1 = is32Bit ? Int(buffer.load(fromByteOffset: base, as: UInt32.self)) : Int(buffer.load(fromByteOffset: base, as: UInt16.self))
                let idx2 = is32Bit ? Int(buffer.load(fromByteOffset: base+4, as: UInt32.self)) : Int(buffer.load(fromByteOffset: base+2, as: UInt16.self))
                let idx3 = is32Bit ? Int(buffer.load(fromByteOffset: base+8, as: UInt32.self)) : Int(buffer.load(fromByteOffset: base+4, as: UInt16.self))
                
                if let n1 = oldToNewMap[idx1], n1 != -1,
                   let n2 = oldToNewMap[idx2], n2 != -1,
                   let n3 = oldToNewMap[idx3], n3 != -1 {
                    newIndices.append(UInt32(n1)); newIndices.append(UInt32(n2)); newIndices.append(UInt32(n3))
                }
            }
        }
        
        if newIndices.isEmpty { throw NSError(domain: "Geo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Resulting mesh has no faces left."]) }
        
        let newElement = SCNGeometryElement(indices: newIndices, primitiveType: .triangles)
        let newGeo = SCNGeometry(sources: newSources, elements: [newElement])
        newGeo.materials = geo.materials
        
        // --- REGENERATE TANGENTS ---
        let mdlMesh = MDLMesh(scnGeometry: newGeo)
        mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                normalAttributeNamed: MDLVertexAttributeNormal,
                                tangentAttributeNamed: MDLVertexAttributeTangent)
        let fixedGeo = SCNGeometry(mdlMesh: mdlMesh)
        fixedGeo.materials = geo.materials
        
        // 5. Export
        let outScene = SCNScene()
        let outNode = SCNNode(geometry: fixedGeo)
        outNode.name = "CleanedModel"
        outScene.rootNode.addChildNode(outNode)
        
        embedTextures(in: outNode)
        
        if format == .usdz {
            outScene.write(to: destinationURL, options: nil, delegate: nil, progressHandler: nil)
        } else {
            let asset = MDLAsset(scnScene: outScene)
            try asset.export(to: destinationURL)
        }
    }
    
    private static func embedTextures(in node: SCNNode) {
        node.enumerateChildNodes { child, _ in child.geometry?.materials.forEach { embedMaterial($0) } }
        node.geometry?.materials.forEach { embedMaterial($0) }
    }
    
    private static func embedMaterial(_ mat: SCNMaterial) {
        embedProperty(mat.diffuse); embedProperty(mat.normal); embedProperty(mat.roughness)
        embedProperty(mat.metalness); embedProperty(mat.ambientOcclusion); embedProperty(mat.emission)
    }
    
    private static func embedProperty(_ property: SCNMaterialProperty) {
        if let url = property.contents as? URL {
            #if os(macOS)
            if let image = NSImage(contentsOf: url) { property.contents = image }
            #else
            if let image = UIImage(contentsOfFile: url.path) { property.contents = image }
            #endif
        } else if let path = property.contents as? String {
            let url = URL(fileURLWithPath: path)
            #if os(macOS)
            if let image = NSImage(contentsOf: url) { property.contents = image }
            #else
            if let image = UIImage(contentsOfFile: path) { property.contents = image }
            #endif
        }
    }
}
