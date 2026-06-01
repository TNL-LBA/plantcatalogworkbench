//
//  WorkspaceSelectionView.swift
//  New workspace creation flow and input database picker.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct NewWorkspaceSheetView: View {
    let workspaceManager: WorkspaceManager
    let onCreate: (WorkspaceSummary) -> Void
    let onCancel: () -> Void

    @State private var workspaceName = ""
    @State private var selectedCatalogURL: URL?
    @State private var errorMessage: String?
    @FocusState private var workspaceNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Workspace")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a new workspace from an exported catalog database. The current workspace stays active until creation succeeds.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Text("Workspace Name")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("Workspace name", text: $workspaceName)
                    .textFieldStyle(.roundedBorder)
                    .focused($workspaceNameFieldFocused)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Input Database")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    Button("Choose Input Database") {
                        chooseInputDatabase()
                    }
                    .buttonStyle(.bordered)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCatalogLabel)
                            .foregroundStyle(selectedCatalogURL == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let selectedCatalogURL {
                            Text(selectedCatalogURL.path(percentEncoded: false))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            Text("The copied working database will be stored as `catalog_working.sqlite` inside the new workspace.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }

                Button("Create Workspace") {
                    createWorkspace()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreateWorkspace)
            }
        }
        .padding(24)
        .frame(width: 560)
        .alert("Workspace Error", isPresented: errorPresentedBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            workspaceNameFieldFocused = true
        }
    }

    private var canCreateWorkspace: Bool {
        !workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            selectedCatalogURL != nil
    }

    private var selectedCatalogLabel: String {
        selectedCatalogURL?.lastPathComponent ?? "No input database selected"
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

    private func chooseInputDatabase() {
        let panel = NSOpenPanel()
        panel.title = "Choose Input Database"
        panel.message = "Select the exported SQLite database for the new workspace."
        panel.prompt = "Choose Database"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "sqlite"),
            UTType(filenameExtension: "sqlite3"),
            UTType(filenameExtension: "db")
        ].compactMap { $0 }

        if panel.runModal() == .OK {
            selectedCatalogURL = panel.url
        }
    }

    private func createWorkspace() {
        guard let selectedCatalogURL else {
            errorMessage = "Choose an input database before creating the workspace."
            return
        }

        do {
            let summary = try workspaceManager.createWorkspace(
                named: workspaceName,
                fromCatalogAt: selectedCatalogURL
            )
            onCreate(summary)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
