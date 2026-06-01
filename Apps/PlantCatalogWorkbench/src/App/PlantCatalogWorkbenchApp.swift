//
//  PlantCatalogWorkbenchApp.swift
//  App entry point for the macOS workbench.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

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
