import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum DroppedContentType {
    case model3D(URL)
    case facePhoto(NSImage)
    case libraryItem(URL)
    case unknown
}

class ContentDropManager {
    
    /// Handles the drop providers and determines the content type.
    /// Uses loadObject(ofClass: URL.self) to ensure Sandbox permissions are handled correctly.
    static func handleDrop(providers: [NSItemProvider], completion: @escaping (DroppedContentType) -> Void) -> Bool {
        guard let provider = providers.first else { return false }
        
        // 1. Try loading as a URL Object (Preferred for Sandbox security)
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url = url {
                    DispatchQueue.main.async {
                        processFile(url: url, completion: completion)
                    }
                } else if let error = error {
                    print("❌ Drop Error: \(error.localizedDescription)")
                }
            }
            return true
        }
        
        // 2. Fallback for older file types (String path or raw data)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                // Handle both URL and Data representations
                if let url = item as? URL {
                    DispatchQueue.main.async { processFile(url: url, completion: completion) }
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async { processFile(url: url, completion: completion) }
                }
            }
            return true
        }
        
        return false
    }
    
    private static func processFile(url: URL, completion: @escaping (DroppedContentType) -> Void) {
        // 1. Start Accessing Security Scope (CRITICAL)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        // 2. Copy to Temp Directory immediately
        // SceneKit often fails to read directly from Downloads due to sandboxing
        guard let safeURL = copyToTemp(url: url) else {
            print("❌ Failed to copy file to temp directory.")
            return
        }
        
        let ext = safeURL.pathExtension.lowercased()
        
        // 3. Determine Type
        if ["obj", "stl", "ply", "usdz", "scn"].contains(ext) {
            completion(.model3D(safeURL))
        } else if ["jpg", "jpeg", "png", "heic", "tiff"].contains(ext) {
            if let img = NSImage(contentsOf: safeURL) {
                completion(.facePhoto(img))
            }
        } else {
            // Assume library item or other resource
            completion(.libraryItem(safeURL))
        }
    }
    
    private static func copyToTemp(url: URL) -> URL? {
        do {
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory
            let dst = tempDir.appendingPathComponent(url.lastPathComponent)
            
            // Overwrite if exists
            if fileManager.fileExists(atPath: dst.path) {
                try fileManager.removeItem(at: dst)
            }
            
            try fileManager.copyItem(at: url, to: dst)
            return dst
        } catch {
            print("❌ Error copying to temp: \(error)")
            return nil
        }
    }
}
