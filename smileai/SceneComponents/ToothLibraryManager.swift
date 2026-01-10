import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO
import Combine

enum ToothType: String, CaseIterable {
    case central = "Central"
    case lateral = "Lateral"
    case canine = "Canine"
    case premolar = "Premolar"
    case molar = "Molar"
}

struct ToothTemplate {
    let meshURL: URL
    let type: ToothType
    let normalizedBounds: (min: SCNVector3, max: SCNVector3)
}

// FIX 1: Add @MainActor and ObservableObject conformance
@MainActor
class ToothLibraryManager: ObservableObject {
    
    // FIX 2: Make library @Published for reactivity
    @Published private(set) var library: [ToothType: [ToothTemplate]] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?
    
    // Cache for instantiated teeth
    private var instanceCache: [String: SCNNode] = [:]
    
    init() {}
    
    // FIX 3: Make async to avoid blocking user-interactive thread
    func loadFromFolder(_ urls: [URL]) async throws {
        isLoading = true
        loadError = nil
        
        // Run heavy I/O on background queue
        let templates = await Task.detached(priority: .userInitiated) { [urls] () -> [ToothType: [ToothTemplate]] in
            var tempLibrary: [ToothType: [ToothTemplate]] = [:]
            
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                
                guard url.pathExtension.lowercased() == "obj" else { continue }
                
                let filename = url.deletingPathExtension().lastPathComponent.lowercased()
                var detectedType: ToothType = .central
                
                if filename.contains("lateral") {
                    detectedType = .lateral
                } else if filename.contains("canine") || filename.contains("cuspid") {
                    detectedType = .canine
                } else if filename.contains("premolar") || filename.contains("bicuspid") {
                    detectedType = .premolar
                } else if filename.contains("molar") {
                    detectedType = .molar
                }
                
                if let scene = try? SCNScene(url: url, options: nil),
                   let geoNode = Self.findFirstGeometryNode(in: scene.rootNode),
                   let geo = geoNode.geometry {
                    
                    let bounds = geo.boundingBox
                    let template = ToothTemplate(
                        meshURL: url,
                        type: detectedType,
                        normalizedBounds: bounds
                    )
                    
                    tempLibrary[detectedType, default: []].append(template)
                }
            }
            
            return tempLibrary
        }.value
        
        // Update on main actor
        self.library = templates
        self.isLoading = false
        
        print("✅ Tooth library loaded: \(templates.values.flatMap { $0 }.count) templates")
    }
    
    // Synchronous version for compatibility (delegates to async)
    func loadFromFolder(_ urls: [URL]) throws {
        Task { @MainActor in
            try? await loadFromFolder(urls)
        }
    }
    
    func instantiateTooth(type: ToothType) -> SCNNode? {
        guard let template = library[type]?.first else {
            print("⚠️ No template found for \(type.rawValue)")
            return nil
        }
        
        // Check cache first
        let cacheKey = template.meshURL.path
        if let cached = instanceCache[cacheKey] {
            return cached.clone()
        }
        
        let access = template.meshURL.startAccessingSecurityScopedResource()
        defer { if access { template.meshURL.stopAccessingSecurityScopedResource() } }
        
        guard let scene = try? SCNScene(url: template.meshURL, options: nil),
              let geoNode = Self.findFirstGeometryNode(in: scene.rootNode) else {
            print("⚠️ Failed to load mesh from \(template.meshURL.lastPathComponent)")
            return nil
        }
        
        let node = geoNode.clone()
        configureDentalMaterial(node)
        
        let bounds = template.normalizedBounds
        let height = bounds.max.y - bounds.min.y
        let targetHeight: Float = 0.010
        let scaleFactor = targetHeight / Float(height)
        node.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        
        // Cache the original
        instanceCache[cacheKey] = node
        
        return node.clone()
    }
    
    func getAllTeeth() -> [SCNNode] {
        var allTeeth: [SCNNode] = []
        for type in ToothType.allCases {
            if let tooth = instantiateTooth(type: type) {
                allTeeth.append(tooth)
            }
        }
        return allTeeth
    }
    
    // MARK: - Private Helpers
    
    // FIX 4: Make nonisolated to allow calling from background tasks
    nonisolated private static func findFirstGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findFirstGeometryNode(in: child) { return found }
        }
        return nil
    }
    
    private func configureDentalMaterial(_ node: SCNNode) {
        node.enumerateChildNodes { child, _ in
            child.geometry?.materials.forEach { applyDentalMaterial($0) }
        }
        node.geometry?.materials.forEach { applyDentalMaterial($0) }
    }
    
    private func applyDentalMaterial(_ material: SCNMaterial) {
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(
            calibratedRed: 0.95,
            green: 0.93,
            blue: 0.88,
            alpha: 1.0
        )
        material.roughness.contents = 0.3
        material.metalness.contents = 0.0
        material.specular.contents = NSColor(white: 0.2, alpha: 1.0)
        material.isDoubleSided = true
    }
    
    // Clear cache to free memory
    func clearCache() {
        instanceCache.removeAll()
    }
}
