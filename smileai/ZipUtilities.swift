import Foundation
import UniformTypeIdentifiers

struct ZipUtilities {
    
    /// Unzips a file to a temporary directory and returns the folder URL.
    static func unzip(fileURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", fileURL.path, "-d", tempDir.path]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ZipError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unzip failed."])
        }
        
        // Return the first child directory if the zip contained a wrapper folder,
        // otherwise return the temp dir itself.
        let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        if contents.count == 1, contents.first!.hasDirectoryPath {
            return contents.first!
        }
        
        return tempDir
    }
    
    /// intelligently finds the folder containing images (HEIC, JPG, PNG).
    /// Handles nested folders or flat structures.
    static func findImageSource(in root: URL) -> URL? {
        let fileManager = FileManager.default
        let imageExtensions = ["heic", "heif", "jpg", "jpeg", "png"]
        
        // Helper: Check if a specific folder has images
        func hasImages(_ url: URL) -> Bool {
            guard let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return false }
            // We need at least 10 images to consider it a valid scan source
            let imageCount = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }.count
            return imageCount > 5
        }
        
        // 1. Check Root
        if hasImages(root) { return root }
        
        // 2. Check Subdirectories (Recursive)
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let fileURL as URL in enumerator {
                if try! fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    if hasImages(fileURL) {
                        return fileURL
                    }
                }
            }
        }
        
        return nil
    }
}
