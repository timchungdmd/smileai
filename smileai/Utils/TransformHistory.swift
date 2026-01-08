import Foundation
import SceneKit
import Combine

struct SmileTemplateParams: Equatable {
    var posX: Float
    var posY: Float
    var posZ: Float
    var scale: Float
    var curve: Float
    var length: Float
    var ratio: Float
}

protocol TransformCommand {
    func execute()
    func undo()
    var description: String { get }
}

struct ToothTransformCommand: TransformCommand {
    let toothID: String
    let oldState: ToothState
    let newState: ToothState
    let applyState: (String, ToothState) -> Void
    
    var description: String {
        "Transform \(toothID)"
    }
    
    func execute() {
        applyState(toothID, newState)
    }
    
    func undo() {
        applyState(toothID, oldState)
    }
}

struct BatchTransformCommand: TransformCommand {
    let commands: [ToothTransformCommand]
    
    var description: String {
        "Batch Transform (\(commands.count) teeth)"
    }
    
    func execute() {
        commands.forEach { $0.execute() }
    }
    
    func undo() {
        commands.reversed().forEach { $0.undo() }
    }
}

struct ArchTransformCommand: TransformCommand {
    let oldParams: SmileTemplateParams
    let newParams: SmileTemplateParams
    let applyParams: (SmileTemplateParams) -> Void
    
    var description: String {
        "Arch Transform"
    }
    
    func execute() {
        applyParams(newParams)
    }
    
    func undo() {
        applyParams(oldParams)
    }
}

@MainActor
class TransformHistory: ObservableObject {
    @Published private(set) var undoStack: [TransformCommand] = []
    @Published private(set) var redoStack: [TransformCommand] = []
    
    private let maxHistorySize = 50
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    func pushCommand(_ command: TransformCommand) {
        command.execute()
        
        undoStack.append(command)
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst()
        }
        
        redoStack.removeAll()
        objectWillChange.send()
    }
    
    func undo() {
        guard let command = undoStack.popLast() else { return }
        command.undo()
        redoStack.append(command)
        objectWillChange.send()
    }
    
    func redo() {
        guard let command = redoStack.popLast() else { return }
        command.execute()
        undoStack.append(command)
        objectWillChange.send()
    }
    
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        objectWillChange.send()
    }
    
    func lastCommandDescription() -> String? {
        undoStack.last?.description
    }
}
