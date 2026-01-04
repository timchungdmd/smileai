import SwiftUI

struct AppTabView: View {
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
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
    }
}
