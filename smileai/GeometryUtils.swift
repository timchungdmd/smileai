import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO

class GeometryUtils {
    
    struct CropBounds {
        let min: SCNVector3
        let max: SCNVector3
    }
    
    enum ExportFormat: String, CaseIterable, Identifiable {
        case stl = "stl"
        case obj = "obj"
        case ply = "ply"
        case usdz = "usdz"
        var id: String { self.rawValue }
    }
    
    static func cropAndExport(sourceURL: URL, destinationURL: URL, bounds: CropBounds, format: ExportFormat) throws {
        // 1. Unzip source to temporary directory to access textures
        let unzipDir = try ZipUtilities.unzip(fileURL: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: unzipDir)
        }
        
        // Find the scene file inside the unzipped folder
        let contents = try FileManager.default.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
        guard let sceneFile = contents.first(where: { $0.pathExtension == "usdc" || $0.pathExtension == "usda" }) else {
            throw NSError(domain: "GeoUtils", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find scene file inside USDZ."])
        }
        
        // Base URL for textures is the folder containing the scene file
        let textureBaseURL = sceneFile.deletingLastPathComponent()
        
        // 2. Load the Source Scene
        let scene = try SCNScene(url: sceneFile, options: nil)
        
        // Find geometry node
        var targetNode: SCNNode?
        scene.rootNode.enumerateChildNodes { node, stop in
            if node.geometry != nil {
                targetNode = node
                stop.pointee = true
            }
        }
        
        guard let node = targetNode, let originalGeo = node.geometry else {
            throw NSError(domain: "GeoUtils", code: 2, userInfo: [NSLocalizedDescriptionKey: "No geometry found."])
        }
        
        // 3. RESOLVE MATERIALS (Fixes "Failed to resolve reference" warnings)
        // Convert all relative texture paths (e.g. "0/tex.png") to Absolute URLs (e.g. "file:///tmp/.../0/tex.png")
        for material in originalGeo.materials {
            resolveProperty(material.diffuse, baseURL: textureBaseURL)
            resolveProperty(material.normal, baseURL: textureBaseURL)
            resolveProperty(material.roughness, baseURL: textureBaseURL)
            resolveProperty(material.metalness, baseURL: textureBaseURL)
            resolveProperty(material.ambientOcclusion, baseURL: textureBaseURL)
            resolveProperty(material.emission, baseURL: textureBaseURL)
            resolveProperty(material.transparent, baseURL: textureBaseURL)
            resolveProperty(material.displacement, baseURL: textureBaseURL)
            resolveProperty(material.clearCoat, baseURL: textureBaseURL)
            resolveProperty(material.clearCoatRoughness, baseURL: textureBaseURL)
            resolveProperty(material.clearCoatNormal, baseURL: textureBaseURL)
        }
        
        // 4. Extract & Crop Geometry
        guard let posSource = originalGeo.sources(for: .vertex).first else { return }
        
        func getPosition(at index: Int) -> SCNVector3 {
            let byteOffset = posSource.dataOffset + (index * posSource.dataStride)
            return posSource.data.withUnsafeBytes { buffer in
                let x = buffer.load(fromByteOffset: byteOffset, as: Float.self)
                let y = buffer.load(fromByteOffset: byteOffset + 4, as: Float.self)
                let z = buffer.load(fromByteOffset: byteOffset + 8, as: Float.self)
                return SCNVector3(x, y, z)
            }
        }
        
        guard let element = originalGeo.elements.first else { return }
        
        var newIndices: [UInt32] = []
        var uniqueVertexMap: [Int: Int] = [:]
        var keptOldIndices: [Int] = []
        
        element.data.withUnsafeBytes { buffer in
            let triangleCount = element.primitiveCount
            let is32Bit = element.bytesPerIndex == 4
            
            for t in 0..<triangleCount {
                let i = t * 3
                let idx1, idx2, idx3: Int
                
                if is32Bit {
                    idx1 = Int(buffer.load(fromByteOffset: i * 4, as: UInt32.self))
                    idx2 = Int(buffer.load(fromByteOffset: (i+1) * 4, as: UInt32.self))
                    idx3 = Int(buffer.load(fromByteOffset: (i+2) * 4, as: UInt32.self))
                } else {
                    idx1 = Int(buffer.load(fromByteOffset: i * 2, as: UInt16.self))
                    idx2 = Int(buffer.load(fromByteOffset: (i+1) * 2, as: UInt16.self))
                    idx3 = Int(buffer.load(fromByteOffset: (i+2) * 2, as: UInt16.self))
                }
                
                let v1 = getPosition(at: idx1)
                let v2 = getPosition(at: idx2)
                let v3 = getPosition(at: idx3)
                
                if isInside(v1, bounds) && isInside(v2, bounds) && isInside(v3, bounds) {
                    func keep(_ oldIndex: Int) -> UInt32 {
                        if let newIndex = uniqueVertexMap[oldIndex] { return UInt32(newIndex) }
                        let newIndex = keptOldIndices.count
                        uniqueVertexMap[oldIndex] = newIndex
                        keptOldIndices.append(oldIndex)
                        return UInt32(newIndex)
                    }
                    newIndices.append(keep(idx1))
                    newIndices.append(keep(idx2))
                    newIndices.append(keep(idx3))
                }
            }
        }
        
        if newIndices.isEmpty {
             throw NSError(domain: "GeoUtils", code: 3, userInfo: [NSLocalizedDescriptionKey: "Crop removed the entire model."])
        }
        
        // 5. Rebuild Sources
        let allSources = originalGeo.sources
        var newSources: [SCNGeometrySource] = []
        
        for source in allSources {
            let stride = source.dataStride
            let offset = source.dataOffset
            let componentSize = source.bytesPerComponent * source.componentsPerVector
            let newLength = keptOldIndices.count * stride
            var newData = Data(count: newLength)
            
            newData.withUnsafeMutableBytes { destPtr in
                source.data.withUnsafeBytes { srcPtr in
                    for (newIdx, oldIdx) in keptOldIndices.enumerated() {
                        let srcLoc = (oldIdx * stride) + offset
                        let dstLoc = (newIdx * stride) + offset
                        if srcLoc + componentSize <= srcPtr.count {
                            let srcAddress = srcPtr.baseAddress!.advanced(by: srcLoc)
                            let dstAddress = destPtr.baseAddress!.advanced(by: dstLoc)
                            dstAddress.copyMemory(from: srcAddress, byteCount: componentSize)
                        }
                    }
                }
            }
            
            let newSource = SCNGeometrySource(
                data: newData,
                semantic: source.semantic,
                vectorCount: keptOldIndices.count,
                usesFloatComponents: source.usesFloatComponents,
                componentsPerVector: source.componentsPerVector,
                bytesPerComponent: source.bytesPerComponent,
                dataOffset: source.dataOffset,
                dataStride: source.dataStride
            )
            newSources.append(newSource)
        }
        
        // 6. Create Final Geometry
        let newElement = SCNGeometryElement(indices: newIndices, primitiveType: .triangles)
        let newGeo = SCNGeometry(sources: newSources, elements: [newElement])
        newGeo.materials = originalGeo.materials // Use the materials we resolved earlier
        
        // 7. BUILD A FRESH SCENE (The Fix)
        // We create a brand new SCNScene to break any link to the old broken USD layers.
        let outputScene = SCNScene()
        let outputNode = SCNNode(geometry: newGeo)
        outputNode.name = "CroppedModel"
        outputScene.rootNode.addChildNode(outputNode)
        
        // 8. EXPORT
        if format == .usdz {
            // Write the FRESH scene. SceneKit will see the absolute paths in materials and bundle them.
            let success = outputScene.write(to: destinationURL, options: nil, delegate: nil, progressHandler: nil)
            if !success {
                throw NSError(domain: "GeoUtils", code: 4, userInfo: [NSLocalizedDescriptionKey: "SceneKit failed to write USDZ."])
            }
        } else {
            let asset = MDLAsset(scnScene: outputScene)
            if asset.count == 0 {
                throw NSError(domain: "GeoUtils", code: 5, userInfo: [NSLocalizedDescriptionKey: "ModelIO failed to process scene."])
            }
            try asset.export(to: destinationURL)
        }
    }
    
    // Helper to force paths to be absolute
    private static func resolveProperty(_ property: SCNMaterialProperty, baseURL: URL) {
        if let path = property.contents as? String {
            let fullURL = baseURL.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fullURL.path) {
                property.contents = fullURL
            }
        } else if let url = property.contents as? URL {
             // If URL is relative or weird, try to fix it
             if !FileManager.default.fileExists(atPath: url.path) {
                 let fixedURL = baseURL.appendingPathComponent(url.lastPathComponent)
                 if FileManager.default.fileExists(atPath: fixedURL.path) {
                     property.contents = fixedURL
                 }
             }
        }
    }
    
    private static func isInside(_ v: SCNVector3, _ b: CropBounds) -> Bool {
        return v.x >= b.min.x && v.x <= b.max.x &&
               v.y >= b.min.y && v.y <= b.max.y &&
               v.z >= b.min.z && v.z <= b.max.z
    }
}
