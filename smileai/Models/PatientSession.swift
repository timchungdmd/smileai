import Foundation
import SceneKit
import Combine

@MainActor
class PatientSession: ObservableObject {
    @Published var activeScanURL: URL?
    @Published var hasUnsavedChanges: Bool = false
}
