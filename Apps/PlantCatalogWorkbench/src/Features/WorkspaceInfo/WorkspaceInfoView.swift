//
//  WorkspaceInfoView.swift
//  Form view for inspecting and editing workspace metadata.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import SwiftUI

@MainActor
struct WorkspaceInfoView: View {
    let workspaceSummary: WorkspaceSummary
    let workspaceRootURL: URL
    let workspaceManager: WorkspaceManager
    let onWorkspaceUpdated: (WorkspaceSummary) -> Void

    @State private var editableDescription: String
    @State private var errorMessage: String?
    @FocusState private var isDescriptionFocused: Bool

    init(
        workspaceSummary: WorkspaceSummary,
        workspaceRootURL: URL,
        workspaceManager: WorkspaceManager,
        onWorkspaceUpdated: @escaping (WorkspaceSummary) -> Void
    ) {
        self.workspaceSummary = workspaceSummary
        self.workspaceRootURL = workspaceRootURL
        self.workspaceManager = workspaceManager
        self.onWorkspaceUpdated = onWorkspaceUpdated
        _editableDescription = State(initialValue: workspaceSummary.workspaceDescription)
    }

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Name") {
                    Text(workspaceSummary.displayName)
                        .textSelection(.enabled)
                }

                LabeledContent("Created") {
                    Text(workspaceSummary.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .textSelection(.enabled)
                }

                LabeledContent("Workspace Folder") {
                    Text(displayedWorkspaceFolderPath)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                LabeledContent("Catalog Database") {
                    Text(workspaceSummary.catalogURL.lastPathComponent)
                        .textSelection(.enabled)
                }
            }

            Section("Description") {
                TextEditor(text: $editableDescription)
                    .font(.body)
                    .frame(minHeight: 140)
                    .focused($isDescriptionFocused)

                HStack {
                    Spacer()
                    Button("Revert") {
                        revertDescription()
                    }
                    .disabled(!canSaveOrRevert)

                    Button("Save") {
                        saveDescription()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSaveOrRevert)
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Workspace Info")
        .onChange(of: workspaceSummary.id) { _, _ in
            editableDescription = workspaceSummary.workspaceDescription
        }
        .alert("Workspace Error", isPresented: errorPresentedBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var hasUnsavedChanges: Bool {
        editableDescription != workspaceSummary.workspaceDescription
    }

    private var canSaveOrRevert: Bool {
        isDescriptionFocused && hasUnsavedChanges
    }

    private var displayedWorkspaceFolderPath: String {
        let fullPath = workspaceSummary.workspaceURL.path(percentEncoded: false)
        let workspaceRootPath = workspaceRootURL.path(percentEncoded: false)
        let applicationSupportPath = workspaceRootURL
            .deletingLastPathComponent()
            .path(percentEncoded: false)
        let applicationSupportPrefix = applicationSupportPath.hasSuffix("/")
            ? applicationSupportPath
            : "\(applicationSupportPath)/"

        if fullPath.hasPrefix(applicationSupportPrefix) {
            return String(fullPath.dropFirst(applicationSupportPrefix.count))
        }

        let workspaceRootPrefix = workspaceRootPath.hasSuffix("/")
            ? workspaceRootPath
            : "\(workspaceRootPath)/"

        if fullPath.hasPrefix(workspaceRootPrefix) {
            return String(fullPath.dropFirst(workspaceRootPrefix.count))
        }

        return fullPath
    }

    private var errorPresentedBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func revertDescription() {
        editableDescription = workspaceSummary.workspaceDescription
        isDescriptionFocused = false
    }

    private func saveDescription() {
        do {
            let updatedWorkspace = try workspaceManager.updateWorkspaceDescription(
                for: workspaceSummary,
                to: editableDescription
            )
            onWorkspaceUpdated(updatedWorkspace)
            isDescriptionFocused = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
