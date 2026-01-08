import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct GenericFile: FileDocument {
    static var readableContentTypes: [UTType] { [UTType.data] }
    
    var sourceURL: URL?
    
    init(sourceURL: URL?) {
        self.sourceURL = sourceURL
    }
    
    init(configuration: ReadConfiguration) throws {}
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = sourceURL else {
            throw NSError(domain: "FileError", code: 1, userInfo: nil)
        }
        return try FileWrapper(url: url)
    }
}

struct STLExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "stl")!] }
    
    var sourceURL: URL?
    
    init(sourceURL: URL?) {
        self.sourceURL = sourceURL
    }
    
    init(configuration: ReadConfiguration) throws {}
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = sourceURL else {
            throw NSError(domain: "FileError", code: 1, userInfo: nil)
        }
        return try FileWrapper(url: url)
    }
}

extension UTType {
    static let stl = UTType(filenameExtension: "stl")!
    static let obj = UTType(filenameExtension: "obj")!
}
