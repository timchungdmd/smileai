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
            throw NSError(domain: "Geo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid geometry"])
        }
        
        // 2. Map Indices
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
        
        if keptIndexCount == 0 { throw NSError(domain: "Geo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mesh deleted"]) }
        
        // 3. Rebuild Vertices
        var newSources: [SCNGeometrySource] = []
        for source in geo.sources {
            let srcStride = source.dataStride
            let srcOffset = source.dataOffset
            let componentSize = source.bytesPerComponent * source.componentsPerVector
            let dstStride = componentSize
            
            var newData = Data(count: keptIndexCount * dstStride)
            source.data.withUnsafeBytes { srcPtr in
                newData.withUnsafeMutableBytes { dstPtr in
                    var dstIndex = 0
                    for i in 0..<vertexSource.vectorCount {
                        if oldToNewMap[i]! != -1 {
                            let srcLoc = i * srcStride + srcOffset
                            if srcLoc + componentSize <= srcPtr.count {
                                let srcAddr = srcPtr.baseAddress!.advanced(by: srcLoc)
                                let dstAddr = dstPtr.baseAddress!.advanced(by: dstIndex * dstStride)
                                dstAddr.copyMemory(from: srcAddr, byteCount: componentSize)
                            }
                            dstIndex += 1
                        }
                    }
                }
            }
            let newSource = SCNGeometrySource(data: newData, semantic: source.semantic, vectorCount: keptIndexCount, usesFloatComponents: source.usesFloatComponents, componentsPerVector: source.componentsPerVector, bytesPerComponent: source.bytesPerComponent, dataOffset: 0, dataStride: dstStride)
            newSources.append(newSource)
        }
        
        // 4. Rebuild Faces
        var newIndices: [UInt32] = []
        element.data.withUnsafeBytes { buf in
            let count = element.primitiveCount
            let is32 = element.bytesPerIndex == 4
            for t in 0..<count {
                let i = t * 3
                let b = i * element.bytesPerIndex
                let idx1 = is32 ? Int(buf.load(fromByteOffset: b, as: UInt32.self)) : Int(buf.load(fromByteOffset: b, as: UInt16.self))
                let idx2 = is32 ? Int(buf.load(fromByteOffset: b+4, as: UInt32.self)) : Int(buf.load(fromByteOffset: b+2, as: UInt16.self))
                let idx3 = is32 ? Int(buf.load(fromByteOffset: b+8, as: UInt32.self)) : Int(buf.load(fromByteOffset: b+4, as: UInt16.self))
                if let n1 = oldToNewMap[idx1], n1 != -1, let n2 = oldToNewMap[idx2], n2 != -1, let n3 = oldToNewMap[idx3], n3 != -1 {
                    newIndices.append(UInt32(n1)); newIndices.append(UInt32(n2)); newIndices.append(UInt32(n3))
                }
            }
        }
        
        if newIndices.isEmpty { throw NSError(domain: "Geo", code: 3, userInfo: [NSLocalizedDescriptionKey: "No faces left"]) }
        
        let newElement = SCNGeometryElement(indices: newIndices, primitiveType: .triangles)
        let newGeo = SCNGeometry(sources: newSources, elements: [newElement])
        newGeo.materials = geo.materials
        
        // --- FIX: REMOVED TANGENT GENERATION ---
        // Skipping MDLMesh conversion entirely to prevent "realloc" crashes on bad topology.
        // The mesh will save with normals but no tangents (visuals are fine for dental).
        
        saveScene(geo: newGeo, sourceURL: sourceURL, destinationURL: destinationURL, format: format)
    }
    
    private static func saveScene(geo: SCNGeometry, sourceURL: URL, destinationURL: URL, format: ExportFormat) {
        let outScene = SCNScene()
        let outNode = SCNNode(geometry: geo)
        outNode.name = "CleanedModel"
        outScene.rootNode.addChildNode(outNode)
        
        embedTextures(in: outNode, relativeTo: sourceURL)
        
        if format == .usdz {
            outScene.write(to: destinationURL, options: nil, delegate: nil, progressHandler: nil)
        } else {
            let asset = MDLAsset(scnScene: outScene)
            try? asset.export(to: destinationURL)
        }
    }
    
    private static func embedTextures(in node: SCNNode, relativeTo baseURL: URL) {
        let baseFolder = baseURL.deletingLastPathComponent()
        let embed = { (prop: SCNMaterialProperty) in
            if let path = prop.contents as? String {
                let fullURL = baseFolder.appendingPathComponent(path)
                #if os(macOS)
                if let img = NSImage(contentsOf: fullURL) { prop.contents = img }
                #else
                if let img = UIImage(contentsOfFile: fullURL.path) { prop.contents = img }
                #endif
            } else if let url = prop.contents as? URL {
                #if os(macOS)
                if let img = NSImage(contentsOf: url) { prop.contents = img }
                #else
                if let img = UIImage(contentsOfFile: url.path) { prop.contents = img }
                #endif
            }
        }
        node.enumerateChildNodes { child, _ in child.geometry?.materials.forEach { mat in
            embed(mat.diffuse); embed(mat.normal); embed(mat.roughness); embed(mat.metalness)
        }}
        node.geometry?.materials.forEach { mat in
            embed(mat.diffuse); embed(mat.normal); embed(mat.roughness); embed(mat.metalness)
        }
    }
}
