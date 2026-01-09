import SceneKit
import AppKit

class ToothDropHandler {
    
    /// Result of a drop operation
    enum DropTarget {
        case tooth(String)      // Dropped on a specific tooth (e.g. "T_1_L")
        case background         // Dropped on background/empty space
        case patientModel       // Dropped on the scan itself
        case none
    }
    
    /// Processes a drag-and-drop operation inside the 3D View
    /// - Parameters:
    ///   - view: The SCNView receiving the drop.
    ///   - sender: The dragging info from macOS.
    /// - Returns: A tuple containing the target type and the file URL (if valid).
    static func handleDrop(in view: SCNView, sender: NSDraggingInfo) -> (target: DropTarget, url: URL)? {
        
        // 1. Get the File URL from Pasteboard
        guard let pasteboard = sender.draggingPasteboard.propertyList(forType: .fileURL) as? String,
              let url = URL(string: pasteboard) else {
            return nil
        }
        
        // 2. Validate Extension (only 3D files)
        let ext = url.pathExtension.lowercased()
        guard ["obj", "stl", "ply", "usdz", "scn"].contains(ext) else {
            return nil
        }
        
        // 3. Hit Test to find what was under the mouse
        let loc = view.convert(sender.draggingLocation, from: nil)
        let hitOptions: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .ignoreHiddenNodes: true
        ]
        
        let hits = view.hitTest(loc, options: hitOptions)
        
        // 4. Determine Target
        if let hit = hits.first {
            // Check if we hit a template tooth
            // Traverses up to find the parent node named "T_..."
            if let toothNode = findParentToothNode(from: hit.node) {
                return (.tooth(toothNode.name!), url)
            }
            
            // Check if we hit the patient scan
            if hit.node.name == "PATIENT_MODEL" {
                return (.patientModel, url)
            }
        }
        
        // Default: Dropped in empty space
        return (.background, url)
    }
    
    /// Helper to find a parent node starting with "T_" (Tooth)
    private static func findParentToothNode(from node: SCNNode) -> SCNNode? {
        if let name = node.name, name.starts(with: "T_") {
            return node
        }
        if let parent = node.parent {
            return findParentToothNode(from: parent)
        }
        return nil
    }
}
