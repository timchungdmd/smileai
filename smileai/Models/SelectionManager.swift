//
//  SelectionModels.swift
//  smileai
//
//  Created by Tim Chung on 1/7/26.
//

import Foundation
import SceneKit
import Combine

@MainActor
class SelectionManager: ObservableObject {
    @Published var selectedToothIDs: Set<String> = []
    @Published var mirrorMode: Bool = false
    
    var hasSelection: Bool { !selectedToothIDs.isEmpty }
    var selectionCount: Int { selectedToothIDs.count }
    
    func selectTooth(_ id: String, multiSelect: Bool) {
        if multiSelect {
            if selectedToothIDs.contains(id) {
                selectedToothIDs.remove(id)
            } else {
                selectedToothIDs.insert(id)
            }
        } else {
            selectedToothIDs = [id]
        }
        objectWillChange.send()
    }
    
    func deselectAll() {
        selectedToothIDs.removeAll()
        objectWillChange.send()
    }
    
    func isSelected(_ id: String) -> Bool {
        selectedToothIDs.contains(id)
    }
    
    func selectRegion(from: String, to: String, allTeeth: [String]) {
        guard let startIdx = allTeeth.firstIndex(of: from),
              let endIdx = allTeeth.firstIndex(of: to) else { return }
        
        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
        selectedToothIDs = Set(allTeeth[range])
        objectWillChange.send()
    }
    
    func getMirrorToothID(_ id: String) -> String? {
        if id.hasSuffix("_R") {
            return id.replacingOccurrences(of: "_R", with: "_L")
        } else if id.hasSuffix("_L") {
            return id.replacingOccurrences(of: "_L", with: "_R")
        }
        return nil
    }
    
    func shouldMirror(_ id: String) -> Bool {
        mirrorMode && getMirrorToothID(id) != nil
    }
}
