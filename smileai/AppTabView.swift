import SwiftUI

struct AppTabView: View {
    var body: some View {
        TabView {
            ScannerContainerView()
                .tabItem {
                    Label("Scanner", systemImage: "cube.transparent")
                }
            
            SmileDesignView()
                .tabItem {
                    Label("Design", systemImage: "wand.and.stars")
                }
        }
    }
}
