import Foundation

@MainActor
struct AppContainer {
    let workspaceManager: WorkspaceManager
    let dateProvider: () -> Date

    static let live = AppContainer(
        workspaceManager: WorkspaceManager(),
        dateProvider: Date.init
    )
}
