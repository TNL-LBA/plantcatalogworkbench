//
//  PlantListFeatureTests.swift
//  Unit tests for plant list paging and filtering.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import SQLite3
import XCTest
@testable import PlantCatalogWorkbench

final class PlantListFeatureTests: XCTestCase {
    func testSQLGuardAcceptsSafeSelect() throws {
        let sql = """
            SELECT p.plant_id, p.botanical_name
            FROM plants p
            WHERE p.botanical_name LIKE ?
            LIMIT 100
            """

        let validatedSQL = try PlantSQLGuard.validate(sql: sql, maximumLimit: 100)

        XCTAssertTrue(validatedSQL.contains("SELECT"))
    }

    func testSQLGuardRejectsWriteStatement() {
        XCTAssertThrowsError(
            try PlantSQLGuard.validate(sql: "DELETE FROM plants LIMIT 1", maximumLimit: 100)
        ) { error in
            XCTAssertEqual(error as? PlantSQLGuard.SQLGuardError, .unsupportedStatement)
        }
    }

    func testSQLGuardRejectsMultipleStatements() {
        XCTAssertThrowsError(
            try PlantSQLGuard.validate(sql: "SELECT * FROM plants LIMIT 1; SELECT 1", maximumLimit: 100)
        ) { error in
            XCTAssertEqual(error as? PlantSQLGuard.SQLGuardError, .multipleStatements)
        }
    }

    func testSQLGuardRejectsUnknownTable() {
        XCTAssertThrowsError(
            try PlantSQLGuard.validate(sql: "SELECT * FROM users LIMIT 1", maximumLimit: 100)
        ) { error in
            XCTAssertEqual(error as? PlantSQLGuard.SQLGuardError, .unknownTable("users"))
        }
    }

    func testSQLGuardRejectsUnknownColumn() {
        XCTAssertThrowsError(
            try PlantSQLGuard.validate(sql: "SELECT private_note FROM plants LIMIT 1", maximumLimit: 100)
        ) { error in
            XCTAssertEqual(error as? PlantSQLGuard.SQLGuardError, .unknownColumn("private_note"))
        }
    }

    func testSQLGuardRejectsTooLargeLimit() {
        XCTAssertThrowsError(
            try PlantSQLGuard.validate(sql: "SELECT * FROM plants LIMIT 500", maximumLimit: 100)
        ) { error in
            XCTAssertEqual(error as? PlantSQLGuard.SQLGuardError, .limitTooLarge(500))
        }
    }

    func testRepositoryFetchesPagedRowsAndCapturesSQL() async throws {
        let databaseURL = try makePlantDatabase(rowCount: 125)
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let repository = try GRDBPlantRepository(catalogURL: databaseURL)
        let page = try await repository.fetchPage(query: .empty, limit: 25, offset: 50)

        XCTAssertEqual(page.rows.count, 25)
        XCTAssertEqual(page.rows.first?.plantID, 51)
        XCTAssertEqual(page.totalCount, 125)
        XCTAssertTrue(page.sqlPreview.sql.contains("LIMIT 25 OFFSET 50"))
    }

    @MainActor
    func testViewModelUsesFakeModelFilterAndLoadsFirstPage() async throws {
        let repository = FakePlantRepository()
        let modelService = FakePlantFilterModelService(state: .ready(.empty))
        let viewModel = PlantListViewModel(
            repository: repository,
            modelService: modelService,
            pageSize: 10,
            maximumCachedPages: 2
        )

        viewModel.filterText = "white flowers"
        viewModel.filterTextDidChange()
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(viewModel.rows.count, 10)
        XCTAssertEqual(repository.fetchRequests.count, 1)
    }

    @MainActor
    func testViewModelFallsBackWhenModelUnavailable() async throws {
        let repository = FakePlantRepository()
        let modelService = FakePlantFilterModelService(state: .modelUnavailable("Unavailable"))
        let viewModel = PlantListViewModel(
            repository: repository,
            modelService: modelService,
            pageSize: 10,
            maximumCachedPages: 2
        )

        viewModel.filterText = "rosa"
        viewModel.filterTextDidChange()
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(viewModel.modelStatusMessage, "Unavailable")
        XCTAssertEqual(viewModel.rows.count, 10)
    }

    @MainActor
    func testViewModelKeepsCacheBounded() async throws {
        let repository = FakePlantRepository(totalRows: 50)
        let modelService = FakePlantFilterModelService(state: .ready(.empty))
        let viewModel = PlantListViewModel(
            repository: repository,
            modelService: modelService,
            pageSize: 10,
            maximumCachedPages: 2
        )

        viewModel.start()
        try await Task.sleep(for: .milliseconds(50))
        viewModel.loadMoreIfNeeded(currentRow: viewModel.rows.last)
        try await Task.sleep(for: .milliseconds(50))
        viewModel.loadMoreIfNeeded(currentRow: viewModel.rows.last)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.rows.count, 20)
        XCTAssertEqual(viewModel.rows.first?.plantID, 11)
    }

    private func makePlantDatabase(rowCount: Int) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let databaseURL = directoryURL.appendingPathComponent("plants.sqlite")

        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path(percentEncoded: false), &database) == SQLITE_OK,
              let database else {
            XCTFail("Could not create SQLite database")
            throw NSError(domain: "PlantListFeatureTests", code: 1)
        }
        defer { sqlite3_close(database) }

        let schemaSQL = """
            CREATE TABLE plants (
                plant_id INTEGER PRIMARY KEY,
                botanical_name TEXT NOT NULL,
                botanical_genus TEXT,
                botanical_species TEXT,
                family_name TEXT,
                page_variant TEXT
            );
            """
        XCTAssertEqual(sqlite3_exec(database, schemaSQL, nil, nil, nil), SQLITE_OK)

        for index in 1...rowCount {
            let insertSQL = """
                INSERT INTO plants (
                    plant_id,
                    botanical_name,
                    botanical_genus,
                    botanical_species,
                    family_name,
                    page_variant
                ) VALUES (
                    \(index),
                    'Plant \(String(format: "%03d", index))',
                    'Genus',
                    'species\(index)',
                    'Family',
                    'default'
                );
                """
            XCTAssertEqual(sqlite3_exec(database, insertSQL, nil, nil, nil), SQLITE_OK)
        }

        return databaseURL
    }
}

private final class FakePlantRepository: PlantRepository, @unchecked Sendable {
    private(set) var fetchRequests: [(limit: Int, offset: Int)] = []
    private let totalRows: Int

    init(totalRows: Int = 30) {
        self.totalRows = totalRows
    }

    func fetchPage(query: PlantQuery, limit: Int, offset: Int) async throws -> PlantQueryPage {
        fetchRequests.append((limit, offset))
        let endIndex = min(offset + limit, totalRows)
        let rows = (offset..<endIndex).map { index in
            PlantRow(
                plantID: Int64(index + 1),
                botanicalName: "Plant \(index + 1)",
                botanicalGenus: "Genus",
                botanicalSpecies: "species",
                familyName: "Family",
                pageVariant: "default"
            )
        }
        return PlantQueryPage(
            rows: rows,
            totalCount: totalRows,
            sqlPreview: SQLPreview(
                sql: "SELECT * FROM plants LIMIT \(limit) OFFSET \(offset)",
                parameters: [],
                pageSize: limit,
                offset: offset,
                warning: nil
            )
        )
    }

    func makeDefaultQuery(filterText: String) throws -> PlantQuery {
        .empty
    }

    func executeReadOnlyQuery(sql: String, parameters: [SQLParameter], limit: Int) async throws -> String {
        "[]"
    }
}

private struct FakePlantFilterModelService: PlantFilterModelServicing {
    let state: PlantFilterState

    func resolveFilter(_ filterText: String, repository: PlantRepository) async -> PlantFilterState {
        state
    }
}
