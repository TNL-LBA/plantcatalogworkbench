//
//  PlantListView.swift
//  Lazy plant table with natural-language filtering.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import SwiftUI

struct PlantListView: View {
    let workspaceSummary: WorkspaceSummary
    let modelService: PlantFilterModelServicing

    @State private var viewModel: PlantListViewModel?
    @State private var repositoryLoadError: String?
    @State private var isShowingSQL = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            filterBar

            if isShowingSQL {
                sqlPreview
            }

            content
        }
        .padding(20)
        .task(id: workspaceSummary.id) {
            await configureViewModel()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workspaceSummary.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(workspaceSummary.catalogURL.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let viewModel {
                Text(viewModel.loadedSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)

            TextField(
                "Filter plants with natural language",
                text: Binding(
                    get: { viewModel?.filterText ?? "" },
                    set: { newValue in
                        viewModel?.filterText = newValue
                        viewModel?.filterTextDidChange()
                    }
                )
            )
            .textFieldStyle(.roundedBorder)

            if viewModel?.isResolvingFilter == true {
                ProgressView()
                    .controlSize(.small)
            }

            Toggle("Show SQL", isOn: $isShowingSQL)
                .toggleStyle(.switch)
                .fixedSize()

            Button {
                viewModel?.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh plants")
            .disabled(viewModel == nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let repositoryLoadError {
            ContentUnavailableView(
                "Cannot Open Plant Catalog",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(repositoryLoadError)
            )
        } else if let viewModel {
            if let errorMessage = viewModel.errorMessage {
                statusBanner(message: errorMessage, systemImage: "exclamationmark.triangle")
            }

            if let modelStatusMessage = viewModel.modelStatusMessage {
                statusBanner(message: modelStatusMessage, systemImage: "sparkles")
            }

            if viewModel.rows.isEmpty, viewModel.isLoadingPage {
                ProgressView("Loading plants...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.rows.isEmpty {
                ContentUnavailableView(
                    "No Plants Found",
                    systemImage: "leaf",
                    description: Text("Adjust the filter to show matching plant rows.")
                )
            } else {
                plantTable(viewModel: viewModel)
            }
        } else {
            ProgressView("Opening plant catalog...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sqlPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current SQL")
                .font(.headline)

            if let preview = viewModel?.sqlPreview {
                ScrollView(.horizontal) {
                    Text(preview.sql)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Parameters: \(parameterDescription(preview.parameters))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Page size \(preview.pageSize), offset \(preview.offset)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = preview.warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("SQL will appear after the first page is loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Builds the SwiftUI table for plant rows.
    /// - Parameter viewModel: Loaded plant list view model.
    /// - Returns: Plant table.
    /// - Throws: Never.
    /// - Side Effects: Row appearance can request the next page.
    private func plantTable(viewModel: PlantListViewModel) -> some View {
        Table(viewModel.rows) {
            TableColumn("ID") { plant in
                Text("\(plant.plantID)")
                    .monospacedDigit()
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentRow: plant)
                    }
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("Botanical Name") { plant in
                Text(plant.botanicalName)
            }
            .width(min: 220, ideal: 320)

            TableColumn("Genus") { plant in
                Text(plant.botanicalGenus ?? "")
            }
            .width(min: 120, ideal: 160)

            TableColumn("Species") { plant in
                Text(plant.botanicalSpecies ?? "")
            }
            .width(min: 120, ideal: 160)

            TableColumn("Family") { plant in
                Text(plant.familyName ?? "")
            }
            .width(min: 140, ideal: 190)

            TableColumn("Variant") { plant in
                Text(plant.pageVariant ?? "")
            }
            .width(min: 90, ideal: 120)
        }
        .overlay(alignment: .bottom) {
            if viewModel.isLoadingPage {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 8)
            }
        }
    }

    /// Creates a compact status banner.
    /// - Parameters:
    ///   - message: Status message.
    ///   - systemImage: SF Symbol name.
    /// - Returns: Banner view.
    /// - Throws: Never.
    /// - Side Effects: None.
    private func statusBanner(message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }

    /// Creates a user-readable parameter list.
    /// - Parameter parameters: SQL parameters.
    /// - Returns: Display text.
    /// - Throws: Never.
    /// - Side Effects: None.
    private func parameterDescription(_ parameters: [SQLParameter]) -> String {
        guard !parameters.isEmpty else {
            return "none"
        }

        return parameters.map(\.description).joined(separator: ", ")
    }

    /// Opens the workspace repository and starts the initial page load.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: Opens SQLite and mutates view state.
    private func configureViewModel() async {
        do {
            let repository = try GRDBPlantRepository(catalogURL: workspaceSummary.catalogURL)
            let viewModel = PlantListViewModel(repository: repository, modelService: modelService)
            self.viewModel = viewModel
            repositoryLoadError = nil
            viewModel.start()
        } catch {
            repositoryLoadError = error.localizedDescription
            viewModel = nil
        }
    }
}
