import SwiftUI

@main
struct DentalStudioApp: App {
    // Shared session to hold the 3D model
    @StateObject private var session = PatientSession()
    
    var body: some Scene {
        WindowGroup {
            AppTabView()
                .environmentObject(session)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
