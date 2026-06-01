import Observation
import SwiftUI

@main
struct PlantCatalogWorkbenchApp: App {
    @State private var workspaceSession = WorkspaceSession()

    var body: some Scene {
        WindowGroup {
            AppShellView(
                container: AppContainer.live,
                workspaceSession: workspaceSession
            )
        }
        .defaultSize(width: 1280, height: 820)
    }
}
