import Foundation
import Combine

class PatientSession: ObservableObject {
    // The shared patient scan URL
    @Published var activeScanURL: URL?
    // The shared template URL
    @Published var activeTemplateURL: URL?
}
