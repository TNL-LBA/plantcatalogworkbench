//
//  AppShellView.swift
//  Main navigation shell for the workbench UI.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import AppKit
import OSLog
import SwiftUI

private enum SidebarDestination: Hashable {
    case info
    case plants
    case audit
}

private enum SidebarLogger {
    static let logger = Logger(
        subsystem: "nl.tientijd.PlantCatalogWorkbench",
        category: "Sidebar"
    )
}

@MainActor
struct AppShellView: View {
    let container: AppContainer
    let workspaceSession: WorkspaceSession

    @State private var selectedDestination: SidebarDestination? = .info
    @State private var isPresentingNewWorkspaceSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                workspaceManager: container.workspaceManager,
                workspaceSession: workspaceSession,
                selectedDestination: $selectedDestination,
                isPresentingNewWorkspaceSheet: $isPresentingNewWorkspaceSheet
            )
        } detail: {
            Group {
                switch selectedDestination ?? .info {
                case .info:
                    if let workspace = workspaceSession.currentWorkspace {
                        WorkspaceInfoView(
                            workspaceSummary: workspace,
                            workspaceRootURL: container.workspaceManager.workspaceRootDirectoryURL,
                            workspaceManager: container.workspaceManager,
                            onWorkspaceUpdated: workspaceSession.updateCurrentWorkspace
                        )
                    } else {
                        EmptyWorkbenchDetailView()
                    }
                case .plants:
                    if let workspace = workspaceSession.currentWorkspace {
                        PlantListView(
                            workspaceSummary: workspace,
                            modelService: container.plantFilterModelService
                        )
                    } else {
                        EmptyWorkbenchDetailView()
                    }
                case .audit:
                    if workspaceSession.currentWorkspace != nil {
                        AuditViewerView()
                    } else {
                        EmptyWorkbenchDetailView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $isPresentingNewWorkspaceSheet) {
            NewWorkspaceSheetView(
                workspaceManager: container.workspaceManager,
                onCreate: { summary in
                    workspaceSession.openWorkspace(summary)
                    selectedDestination = .info
                    isPresentingNewWorkspaceSheet = false
                },
                onCancel: {
                    isPresentingNewWorkspaceSheet = false
                }
            )
        }
    }
}

private struct SidebarView: View {
    let workspaceManager: WorkspaceManager
    let workspaceSession: WorkspaceSession
    @Binding var selectedDestination: SidebarDestination?
    @Binding var isPresentingNewWorkspaceSheet: Bool

    @State private var workspaces: [WorkspaceSummary] = []
    @State private var workspaceLoadError: String?

    var body: some View {
        List(selection: $selectedDestination) {
            Section {
                HStack {
                    Text("Workspace")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        refreshWorkspaces()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh workspaces")

                    Button {
                        isPresentingNewWorkspaceSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Create a new workspace")
                }

                if workspaces.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No workspaces found")
                            .foregroundStyle(.secondary)

                        Text(workspaceManager.workspaceRootDirectoryURL.path(percentEncoded: false))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(4)
                            .textSelection(.enabled)

                        if let workspaceLoadError {
                            Text(workspaceLoadError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(workspaces) { workspace in
                    Button {
                        log("workspace selected id=\(workspace.id) name=\(workspace.displayName)")
                        workspaceSession.openWorkspace(workspace)
                        selectedDestination = .info
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                            Text(workspace.displayName)
                            Spacer()
                            if workspace.id == workspaceSession.currentWorkspace?.id {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Toon in Finder") {
                            showWorkspaceInFinder(workspace)
                        }
                    }
                }
            }

            Divider()

            Section("Workbench") {
                if workspaceSession.currentWorkspace != nil {
                    Label("Info", systemImage: "info.circle")
                        .tag(SidebarDestination.info)
                        .contextMenu {
                            Button("Toon in Finder") {
                                showCurrentWorkspaceInFinder()
                            }
                        }
                    Label("Plants", systemImage: "leaf")
                        .tag(SidebarDestination.plants)
                    Label("Audit", systemImage: "doc.text.magnifyingglass")
                        .tag(SidebarDestination.audit)
                }
            }
        }
        .navigationTitle("Plant Catalog Workbench")
        .onAppear(perform: refreshWorkspaces)
        .onChange(of: workspaceSession.currentWorkspace?.id) { _, _ in
            refreshWorkspaces()
        }
    }

    private func refreshWorkspaces() {
        log("refreshWorkspaces: start")
        do {
            workspaceLoadError = nil
            workspaces = try workspaceManager.listWorkspaces()
            log("refreshWorkspaces: loaded \(workspaces.count) workspaces")
        } catch {
            workspaces = []
            workspaceLoadError = error.localizedDescription
            log("refreshWorkspaces: failed with error=\(error)")
        }
    }

    private func showCurrentWorkspaceInFinder() {
        guard let workspaceURL = workspaceSession.currentWorkspace?.workspaceURL else {
            log("showCurrentWorkspaceInFinder: no current workspace")
            return
        }

        log("showCurrentWorkspaceInFinder: \(workspaceURL.path(percentEncoded: false))")
        NSWorkspace.shared.activateFileViewerSelecting([workspaceURL])
    }

    private func showWorkspaceInFinder(_ workspace: WorkspaceSummary) {
        log("showWorkspaceInFinder: \(workspace.workspaceURL.path(percentEncoded: false))")
        NSWorkspace.shared.activateFileViewerSelecting([workspace.workspaceURL])
    }

    private func log(_ message: String) {
        SidebarLogger.logger.debug("\(message, privacy: .public)")
    }
}

private struct EmptyWorkbenchDetailView: View {
    var body: some View {
        ContentUnavailableView(
            "No Workspace Open",
            systemImage: "folder.badge.plus",
            description: Text("Create a new workspace with the plus button in the sidebar, or open one from the workspace list.")
        )
    }
}
