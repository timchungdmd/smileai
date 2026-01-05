import SwiftUI
import UniformTypeIdentifiers

struct STLFile: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "stl")!] }
    
    var sourceURL: URL?
    
    init(sourceURL: URL?) {
        self.sourceURL = sourceURL
    }
    
    init(configuration: ReadConfiguration) throws { }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // If we have a source URL (the exported STL on disk), read it
        if let source = sourceURL, let data = try? Data(contentsOf: source) {
            return FileWrapper(regularFileWithContents: data)
        }
        return FileWrapper(regularFileWithContents: Data())
    }
}
