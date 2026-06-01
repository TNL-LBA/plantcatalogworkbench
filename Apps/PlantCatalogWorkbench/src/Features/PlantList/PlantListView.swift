//
//  PlantListView.swift
//  Placeholder list view for workspace plant data.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import SwiftUI

struct PlantListView: View {
    let workspaceSummary: WorkspaceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(workspaceSummary.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Text(workspaceSummary.sourceCatalogFilename)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Plant list, search, and batch parse actions will live here.")
                .foregroundStyle(.secondary)

            LabeledContent("Workspace Folder") {
                Text(workspaceSummary.workspaceURL.lastPathComponent)
                    .textSelection(.enabled)
            }

            LabeledContent("Catalog Database") {
                Text(workspaceSummary.catalogURL.lastPathComponent)
            }

            LabeledContent("Parse Runs") {
                Text("\(workspaceSummary.parseRunCount)")
            }

            ContentUnavailableView(
                "No Plant Data Yet",
                systemImage: "leaf.circle",
                description: Text("Connect GRDB-backed queries to show plants from the working catalog.")
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
