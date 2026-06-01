//
//  AppContainer.swift
//  Dependency container for app-level services.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation

@MainActor
struct AppContainer {
    let workspaceManager: WorkspaceManager
    let plantFilterModelService: PlantFilterModelServicing
    let dateProvider: () -> Date

    static let live = Self(
        workspaceManager: WorkspaceManager(),
        plantFilterModelService: PlantFilterModelService(),
        dateProvider: Date.init
    )
}
