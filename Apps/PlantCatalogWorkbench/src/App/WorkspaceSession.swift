//
//  WorkspaceSession.swift
//  Observable workspace selection state for the app shell.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceSession {
    enum State: Equatable {
        case noWorkspaceSelected
        case workspaceOpen(WorkspaceSummary)
    }

    var state: State = .noWorkspaceSelected

    var currentWorkspace: WorkspaceSummary? {
        guard case let .workspaceOpen(summary) = state else {
            return nil
        }

        return summary
    }

    func openWorkspace(_ summary: WorkspaceSummary) {
        state = .workspaceOpen(summary)
    }

    func updateCurrentWorkspace(_ summary: WorkspaceSummary) {
        guard summary.id == currentWorkspace?.id else {
            return
        }

        state = .workspaceOpen(summary)
    }

    func closeWorkspace() {
        state = .noWorkspaceSelected
    }
}
