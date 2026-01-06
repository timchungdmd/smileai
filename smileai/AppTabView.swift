import SwiftUI

struct AppTabView: View {
    @EnvironmentObject var session: PatientSession
    @State private var selectedTab: Int = 0
    
    // Alert State
    @State private var showUnsavedAlert: Bool = false
    @State private var pendingTab: Int? = nil
    
    var body: some View {
        // Custom Binding to intercept tab clicks
        let tabBinding = Binding<Int>(
            get: { selectedTab },
            set: { newTab in
                if newTab == 0 && (session.activeScanURL != nil || session.activeTemplateURL != nil) {
                    // Trying to go back to Scan (0) while Design (1) has data
                    pendingTab = newTab
                    showUnsavedAlert = true
                } else {
                    selectedTab = newTab
                }
            }
        )
        
        TabView(selection: tabBinding) {
            ScannerContainerView()
                .tabItem {
                    Label("Scan & Process", systemImage: "arrow.triangle.2.circlepath.camera.fill")
                }
                .tag(0)
            
            SmileDesignView()
                .tabItem {
                    Label("Smile Design", systemImage: "mouth.fill")
                }
                .tag(1)
        }
        .padding()
        // The Safety Popup
        .alert("Discard Changes?", isPresented: $showUnsavedAlert) {
            Button("Cancel", role: .cancel) {
                pendingTab = nil
            }
            Button("Discard & Leave", role: .destructive) {
                // Clear the session
                session.activeScanURL = nil
                session.activeTemplateURL = nil // If you have a photo variable in session, clear it too
                
                // Proceed to tab
                if let t = pendingTab { selectedTab = t }
                pendingTab = nil
            }
        } message: {
            Text("Going back to Scan & Process will delete the current model and snapshot. Have you saved your project?")
        }
    }
}
