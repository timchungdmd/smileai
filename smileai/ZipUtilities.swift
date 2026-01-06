import Foundation
import UniformTypeIdentifiers

struct ZipUtilities {
    
    /// Unzips a file to a temporary directory.
    /// Marked nonisolated to allow calling from background threads safely.
    nonisolated static func unzip(fileURL: URL) throws -> URL {
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
        
        let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        if contents.count == 1, contents.first!.hasDirectoryPath {
            return contents.first!
        }
        return tempDir
    }
    
    static func findImageSource(in root: URL) -> URL? {
        let fileManager = FileManager.default
        let imageExtensions = ["heic", "heif", "jpg", "jpeg", "png"]
        
        func hasImages(_ url: URL) -> Bool {
            guard let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return false }
            let imageCount = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }.count
            return imageCount > 5
        }
        
        if hasImages(root) { return root }
        
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let fileURL as URL in enumerator {
                if try! fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    if hasImages(fileURL) { return fileURL }
                }
            }
        }
        return nil
    }
}
