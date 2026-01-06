import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO

class GeometryUtils {
    
    enum ExportFormat: String, CaseIterable, Identifiable {
        case stl = "stl"
        case obj = "obj"
        case usdz = "usdz"
        var id: String { rawValue }
    }
    
    /// Deletes specific vertices and connected faces from the mesh, then exports a clean file.
    static func deleteVertices(sourceURL: URL, destinationURL: URL, indicesToDelete: Set<Int>, format: ExportFormat) throws {
        
        // 1. Load Scene
        let scene = try SCNScene(url: sourceURL, options: nil)
        
        // --- NECESSARY UPDATE: Robust Node Finder ---
        // Instead of just checking rootNode.childNodes.first (which fails on nested meshes),
        // we recursively search the entire scene graph for the first node containing geometry.
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
        // -1 means the vertex is deleted.
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
        
        // 3. Rebuild Vertex Sources (Position, Normal, Color, etc.)
        var newSources: [SCNGeometrySource] = []
        
        for source in geo.sources {
            let stride = source.dataStride
            let offset = source.dataOffset
            let componentSize = source.bytesPerComponent * source.componentsPerVector
            
            var newData = Data(count: keptIndexCount * stride)
            
            // Unsafe copy of only the kept vertices
            source.data.withUnsafeBytes { srcPtr in
                newData.withUnsafeMutableBytes { dstPtr in
                    var dstOffset = 0
                    for i in 0..<vertexSource.vectorCount {
                        if oldToNewMap[i]! != -1 {
                            let srcLoc = i * stride + offset
                            if srcLoc + componentSize <= srcPtr.count {
                                let srcAddress = srcPtr.baseAddress!.advanced(by: srcLoc)
                                let dstAddress = dstPtr.baseAddress!.advanced(by: dstOffset + offset)
                                dstAddress.copyMemory(from: srcAddress, byteCount: componentSize)
                            }
                            dstOffset += stride
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
                dataOffset: source.dataOffset,
                dataStride: source.dataStride
            )
            newSources.append(newSource)
        }
        
        // 4. Rebuild Triangles (Indices)
        // We only keep triangles where ALL 3 vertices survived.
        var newIndices: [UInt32] = []
        
        element.data.withUnsafeBytes { buffer in
            let triangleCount = element.primitiveCount
            let is32Bit = element.bytesPerIndex == 4
            
            for t in 0..<triangleCount {
                let i = t * 3
                let base = i * element.bytesPerIndex
                
                let idx1, idx2, idx3: Int
                
                if is32Bit {
                    idx1 = Int(buffer.load(fromByteOffset: base, as: UInt32.self))
                    idx2 = Int(buffer.load(fromByteOffset: base + 4, as: UInt32.self))
                    idx3 = Int(buffer.load(fromByteOffset: base + 8, as: UInt32.self))
                } else {
                    idx1 = Int(buffer.load(fromByteOffset: base, as: UInt16.self))
                    idx2 = Int(buffer.load(fromByteOffset: base + 2, as: UInt16.self))
                    idx3 = Int(buffer.load(fromByteOffset: base + 4, as: UInt16.self))
                }
                
                // If all 3 vertices map to valid new indices, keep the triangle
                if let n1 = oldToNewMap[idx1], n1 != -1,
                   let n2 = oldToNewMap[idx2], n2 != -1,
                   let n3 = oldToNewMap[idx3], n3 != -1 {
                    newIndices.append(UInt32(n1))
                    newIndices.append(UInt32(n2))
                    newIndices.append(UInt32(n3))
                }
            }
        }
        
        let newElement = SCNGeometryElement(indices: newIndices, primitiveType: .triangles)
        let newGeo = SCNGeometry(sources: newSources, elements: [newElement])
        
        // Preserve Materials
        newGeo.materials = geo.materials
        
        // 5. Export New File
        let outScene = SCNScene()
        let outNode = SCNNode(geometry: newGeo)
        outNode.name = "CleanedModel"
        outScene.rootNode.addChildNode(outNode)
        
        if format == .usdz {
            outScene.write(to: destinationURL, options: nil, delegate: nil, progressHandler: nil)
        } else {
            let asset = MDLAsset(scnScene: outScene)
            try asset.export(to: destinationURL)
        }
    }
}
