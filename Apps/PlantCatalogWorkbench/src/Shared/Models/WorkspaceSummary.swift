//
//  WorkspaceSummary.swift
//  Lightweight workspace summary used by the UI.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation

struct WorkspaceSummary: Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let workspaceURL: URL
    let catalogURL: URL
    let auditDirectoryURL: URL
    let sourceCatalogFilename: String
    let createdAt: Date
    let workspaceDescription: String
    let parseRunCount: Int
}
