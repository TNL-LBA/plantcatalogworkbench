//
//  PlantListViewModel.swift
//  View model for the lazy plant table.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class PlantListViewModel {
    var filterText = ""
    var rows: [PlantRow] = []
    var totalCount = 0
    var isLoadingPage = false
    var isResolvingFilter = false
    var errorMessage: String?
    var modelStatusMessage: String?
    var sqlPreview: SQLPreview?

    private let repository: PlantRepository
    private let modelService: PlantFilterModelServicing
    private let pageSize: Int
    private let maximumCachedPages: Int
    private let logger = Logger(
        subsystem: "nl.tientijd.PlantCatalogWorkbench",
        category: "PlantListViewModel"
    )

    private var currentQuery = PlantQuery.empty
    private var loadedRowCount = 0
    private var filterTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?

    var hasMoreRows: Bool {
        rows.count < totalCount || totalCount == 0
    }

    var loadedSummary: String {
        let formattedCount = totalCount.formatted(.number)
        return "\(formattedCount) rows"
    }

    /// Creates the view model that coordinates filtering and lazy loading.
    /// - Parameters:
    ///   - repository: Plant repository for paged database reads.
    ///   - modelService: Natural-language filter service.
    ///   - pageSize: Rows requested per page.
    ///   - maximumCachedPages: Maximum pages retained in memory.
    /// - Returns: Initialized view model.
    /// - Throws: Never.
    /// - Side Effects: None.
    init(
        repository: PlantRepository,
        modelService: PlantFilterModelServicing,
        pageSize: Int = 100,
        maximumCachedPages: Int = 5
    ) {
        self.repository = repository
        self.modelService = modelService
        self.pageSize = pageSize
        self.maximumCachedPages = maximumCachedPages
    }

    /// Starts the first table load.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: Reads the first page from SQLite.
    func start() {
        guard rows.isEmpty, !isLoadingPage else {
            return
        }

        loadFirstPage()
    }

    /// Debounces user filter changes.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: Cancels existing filter and page tasks.
    func filterTextDidChange() {
        filterTask?.cancel()
        pageTask?.cancel()
        filterTask = Task { [filterText] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }
            await resolveFilter(filterText)
        }
    }

    /// Loads more rows when the table approaches the end of the current cache.
    /// - Parameter row: Row that appeared in the table.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: May read the next page from SQLite.
    func loadMoreIfNeeded(currentRow row: PlantRow?) {
        guard let row else {
            loadNextPage()
            return
        }

        guard rows.suffix(12).contains(row) else {
            return
        }

        loadNextPage()
    }

    /// Reloads the current filter from the first page.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: Cancels in-flight work and reads from SQLite.
    func refresh() {
        filterTask?.cancel()
        pageTask?.cancel()
        loadFirstPage()
    }

    /// Resolves filter text through Foundation Models when possible.
    /// - Parameter text: User-entered filter text.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: May invoke Foundation Models and read from SQLite.
    private func resolveFilter(_ text: String) async {
        isResolvingFilter = true
        errorMessage = nil
        modelStatusMessage = nil

        let state = await modelService.resolveFilter(text, repository: repository)
        guard !Task.isCancelled else {
            return
        }

        switch state {
        case .idle, .resolving:
            break
        case let .modelUnavailable(message):
            modelStatusMessage = message
            do {
                currentQuery = try repository.makeDefaultQuery(filterText: text)
            } catch {
                errorMessage = error.localizedDescription
            }
        case let .ready(query):
            currentQuery = query
        case let .failed(message):
            errorMessage = message
            do {
                currentQuery = try repository.makeDefaultQuery(filterText: text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        isResolvingFilter = false
        loadFirstPage()
    }

    /// Clears rows and loads the first page for the current query.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: Reads from SQLite.
    private func loadFirstPage() {
        rows = []
        totalCount = 0
        loadedRowCount = 0
        sqlPreview = nil
        loadNextPage()
    }

    /// Loads the next page if no page load is in flight.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: Reads from SQLite.
    private func loadNextPage() {
        guard !isLoadingPage else {
            return
        }
        guard loadedRowCount == 0 || loadedRowCount < totalCount else {
            return
        }

        isLoadingPage = true
        let query = currentQuery
        let offset = loadedRowCount
        pageTask = Task {
            do {
                let page = try await repository.fetchPage(query: query, limit: pageSize, offset: offset)
                guard !Task.isCancelled else {
                    return
                }
                apply(page: page)
            } catch is CancellationError {
                logger.debug("loadNextPage cancelled")
            } catch {
                errorMessage = error.localizedDescription
                logger.error("loadNextPage failed: \(error.localizedDescription, privacy: .public)")
            }
            isLoadingPage = false
        }
    }

    /// Applies a fetched page to the visible table cache.
    /// - Parameter page: Fetched plant page.
    /// - Returns: Nothing.
    /// - Throws: Never.
    /// - Side Effects: Mutates table state.
    private func apply(page: PlantQueryPage) {
        totalCount = page.totalCount
        loadedRowCount += page.rows.count
        rows.append(contentsOf: page.rows)
        rows = Array(rows.suffix(pageSize * maximumCachedPages))
        sqlPreview = page.sqlPreview
    }
}
