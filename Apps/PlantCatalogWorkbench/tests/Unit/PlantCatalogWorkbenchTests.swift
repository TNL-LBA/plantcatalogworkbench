//
//  PlantCatalogWorkbenchTests.swift
//  Unit tests for workspace and database behaviors.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import XCTest
import SQLite3
@testable import PlantCatalogWorkbench

final class PlantCatalogWorkbenchTests: XCTestCase {
    @MainActor
    func testWorkspaceSessionStartsWithoutWorkspace() {
        let session = WorkspaceSession()

        XCTAssertEqual(session.state, .noWorkspaceSelected)
    }

    @MainActor
    func testDefaultWorkspaceRootUsesApplicationSupport() {
        let manager = WorkspaceManager()
        let workspaceRootURL = manager.workspaceRootDirectoryURL
        let expectedBaseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first

        XCTAssertEqual(workspaceRootURL.lastPathComponent, "Workspaces")
        XCTAssertEqual(workspaceRootURL.deletingLastPathComponent().lastPathComponent, "PlantCatalogWorkbench")

        if let expectedBaseURL {
            XCTAssertTrue(
                workspaceRootURL
                    .path(percentEncoded: false)
                    .hasPrefix(expectedBaseURL.path(percentEncoded: false))
            )
        }
    }

    @MainActor
    func testCreateWorkspaceCopiesCatalogAndWritesMetadata() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? removeTemporaryDirectory(at: temporaryDirectoryURL) }

        let catalogURL = temporaryDirectoryURL.appendingPathComponent("source.sqlite")
        try createSQLiteDatabase(at: catalogURL, schemaKind: .versionOne)

        let workspaceRootURL = temporaryDirectoryURL.appendingPathComponent("workspaces", isDirectory: true)
        let manager = WorkspaceManager(workspaceRootURL: workspaceRootURL)

        let summary = try manager.createWorkspace(named: "Spring Imports", fromCatalogAt: catalogURL)

        XCTAssertEqual(summary.displayName, "Spring Imports")
        XCTAssertEqual(summary.sourceCatalogFilename, "source.sqlite")
        XCTAssertEqual(summary.workspaceDescription, "")
        XCTAssertEqual(summary.parseRunCount, 0)
        XCTAssertEqual(summary.catalogURL.lastPathComponent, "catalog_working.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.workspaceURL.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.catalogURL.path(percentEncoded: false)))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: summary.workspaceURL
                    .appendingPathComponent("workspace-metadata.json")
                    .path(percentEncoded: false)
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.auditDirectoryURL.path(percentEncoded: false)))
    }

    @MainActor
    func testOpenWorkspaceReadsMetadataAndCountsParseRuns() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? removeTemporaryDirectory(at: temporaryDirectoryURL) }

        let catalogURL = temporaryDirectoryURL.appendingPathComponent("source.sqlite")
        try createSQLiteDatabase(at: catalogURL, schemaKind: .versionOne)

        let workspaceRootURL = temporaryDirectoryURL.appendingPathComponent("workspaces", isDirectory: true)
        let manager = WorkspaceManager(workspaceRootURL: workspaceRootURL)
        let createdSummary = try manager.createWorkspace(named: "Review Batch", fromCatalogAt: catalogURL)

        let runOneURL = createdSummary.auditDirectoryURL.appendingPathComponent("run-001.json")
        let runTwoURL = createdSummary.auditDirectoryURL.appendingPathComponent("run-002.json")
        try Data("{}".utf8).write(to: runOneURL)
        try Data("{}".utf8).write(to: runTwoURL)

        let reopenedSummary = try manager.openWorkspace(at: createdSummary.workspaceURL)

        XCTAssertEqual(reopenedSummary.id, createdSummary.id)
        XCTAssertEqual(reopenedSummary.displayName, "Review Batch")
        XCTAssertEqual(reopenedSummary.sourceCatalogFilename, "source.sqlite")
        XCTAssertEqual(reopenedSummary.workspaceDescription, "")
        XCTAssertEqual(reopenedSummary.parseRunCount, 2)
    }

    @MainActor
    func testUpdateWorkspaceDescriptionPersistsToMetadata() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? removeTemporaryDirectory(at: temporaryDirectoryURL) }

        let catalogURL = temporaryDirectoryURL.appendingPathComponent("source.sqlite")
        try createSQLiteDatabase(at: catalogURL, schemaKind: .versionOne)

        let workspaceRootURL = temporaryDirectoryURL.appendingPathComponent("workspaces", isDirectory: true)
        let manager = WorkspaceManager(workspaceRootURL: workspaceRootURL)
        let createdSummary = try manager.createWorkspace(named: "Notes Batch", fromCatalogAt: catalogURL)

        let updatedSummary = try manager.updateWorkspaceDescription(
            for: createdSummary,
            to: "Used for manual review."
        )
        let reopenedSummary = try manager.openWorkspace(at: createdSummary.workspaceURL)

        XCTAssertEqual(updatedSummary.workspaceDescription, "Used for manual review.")
        XCTAssertEqual(reopenedSummary.workspaceDescription, "Used for manual review.")
    }

    @MainActor
    func testListWorkspacesIgnoresIncompleteWorkspaceFolders() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? removeTemporaryDirectory(at: temporaryDirectoryURL) }

        let catalogURL = temporaryDirectoryURL.appendingPathComponent("source.sqlite")
        try createSQLiteDatabase(at: catalogURL, schemaKind: .versionOne)

        let workspaceRootURL = temporaryDirectoryURL.appendingPathComponent("workspaces", isDirectory: true)
        let invalidWorkspaceURL = workspaceRootURL.appendingPathComponent("broken", isDirectory: true)
        let manager = WorkspaceManager(workspaceRootURL: workspaceRootURL)

        let createdSummary = try manager.createWorkspace(named: "Visible Workspace", fromCatalogAt: catalogURL)
        try FileManager.default.createDirectory(at: invalidWorkspaceURL, withIntermediateDirectories: true)

        let workspaces = try manager.listWorkspaces()

        XCTAssertEqual(workspaces.map(\.id), [createdSummary.id])
    }

    @MainActor
    func testListWorkspacesSupportsRootPathWithSpaces() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? removeTemporaryDirectory(at: temporaryDirectoryURL) }

        let catalogURL = temporaryDirectoryURL.appendingPathComponent("source.sqlite")
        try createSQLiteDatabase(at: catalogURL, schemaKind: .versionOne)

        let workspaceRootURL = temporaryDirectoryURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("PlantCatalogWorkbench", isDirectory: true)
            .appendingPathComponent("Workspaces", isDirectory: true)
        let manager = WorkspaceManager(workspaceRootURL: workspaceRootURL)
        let createdSummary = try manager.createWorkspace(named: "Visible Workspace", fromCatalogAt: catalogURL)

        let workspaces = try manager.listWorkspaces()

        XCTAssertEqual(workspaces.map(\.id), [createdSummary.id])
    }

    @MainActor
    func testCreateWorkspaceRejectsDatabaseWithoutSchemaVersionTable() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? removeTemporaryDirectory(at: temporaryDirectoryURL) }

        let catalogURL = temporaryDirectoryURL.appendingPathComponent("source.sqlite")
        try createSQLiteDatabase(at: catalogURL, schemaKind: .withoutSchemaVersionTable)

        let workspaceRootURL = temporaryDirectoryURL.appendingPathComponent("workspaces", isDirectory: true)
        let manager = WorkspaceManager(workspaceRootURL: workspaceRootURL)

        XCTAssertThrowsError(
            try manager.createWorkspace(named: "Invalid Import", fromCatalogAt: catalogURL)
        ) { error in
            XCTAssertEqual(error as? WorkspaceManager.WorkspaceError, .missingDatabaseSchemaVersionsTable)
        }
    }

    @MainActor
    func testCreateWorkspaceRejectsVersionedDatabaseWithInvalidSchema() throws {
        let temporaryDirectoryURL = try makeTemporaryDirectory()
        defer { try? removeTemporaryDirectory(at: temporaryDirectoryURL) }

        let catalogURL = temporaryDirectoryURL.appendingPathComponent("source.sqlite")
        try createSQLiteDatabase(at: catalogURL, schemaKind: .versionOneMissingPlantsTable)

        let workspaceRootURL = temporaryDirectoryURL.appendingPathComponent("workspaces", isDirectory: true)
        let manager = WorkspaceManager(workspaceRootURL: workspaceRootURL)

        XCTAssertThrowsError(
            try manager.createWorkspace(named: "Invalid Import", fromCatalogAt: catalogURL)
        ) { error in
            guard case let .databaseSchemaMismatch(message) = error as? WorkspaceManager.WorkspaceError else {
                XCTFail("Expected database schema mismatch, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Database schema version `1`"))
            XCTAssertTrue(message.contains("missing table"))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryDirectory(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private enum TestCatalogSchemaKind {
        case versionOne
        case withoutSchemaVersionTable
        case versionOneMissingPlantsTable
    }

    private func createSQLiteDatabase(at url: URL, schemaKind: TestCatalogSchemaKind) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path(percentEncoded: false), &database) == SQLITE_OK, let database else {
            sqlite3_close(database)
            XCTFail("Could not create test SQLite database")
            return
        }
        defer { sqlite3_close(database) }

        let sql: String
        switch schemaKind {
        case .versionOne:
            sql = Self.versionOneSchemaSQL
        case .withoutSchemaVersionTable:
            sql = """
                CREATE TABLE plants (
                    plant_id INTEGER PRIMARY KEY,
                    botanical_name TEXT NOT NULL
                );
                """
        case .versionOneMissingPlantsTable:
            sql = """
                CREATE TABLE database_schema_versions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    schema_version TEXT NOT NULL,
                    applied_at TEXT NOT NULL,
                    description TEXT NOT NULL
                );
                INSERT INTO database_schema_versions (
                    schema_version,
                    applied_at,
                    description
                ) VALUES (
                    '1',
                    '2026-06-01T00:00:00Z',
                    'Test schema'
                );
                CREATE TABLE families (id INTEGER PRIMARY KEY, name TEXT);
                """
        }

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            XCTFail("Could not create schema in test SQLite database")
            return
        }
    }

    private static let versionOneSchemaSQL = """
        CREATE TABLE database_schema_versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            schema_version TEXT NOT NULL,
            applied_at TEXT NOT NULL,
            description TEXT NOT NULL
        );
        INSERT INTO database_schema_versions (
            schema_version,
            applied_at,
            description
        ) VALUES (
            '1',
            '2026-06-01T00:00:00Z',
            'Test schema'
        );
        CREATE TABLE plants (
            plant_id INTEGER PRIMARY KEY,
            botanical_name TEXT NOT NULL,
            botanical_genus TEXT,
            botanical_species TEXT,
            botanical_infraspecific_rank TEXT,
            botanical_infraspecific_epithet TEXT,
            botanical_hybrid_marker TEXT,
            botanical_cultivar_group TEXT,
            botanical_cultivar_name TEXT,
            botanical_trade_designation TEXT,
            botanical_qualifiers_text TEXT,
            botanical_authority TEXT,
            botanical_unparsed_remainder TEXT,
            family_name TEXT,
            genus_name TEXT,
            page_variant TEXT
        );
        CREATE TABLE attribute_types (
            attribute_type_id INTEGER PRIMARY KEY,
            attribute_type TEXT NOT NULL UNIQUE,
            value_kind TEXT NOT NULL,
            is_multi_value INTEGER NOT NULL
        );
        CREATE TABLE attributes (
            attribute_id INTEGER PRIMARY KEY,
            plant_id INTEGER NOT NULL,
            attribute_type_id INTEGER NOT NULL,
            region_code TEXT,
            value_text TEXT,
            value_integer INTEGER,
            value_boolean INTEGER,
            value_json TEXT
        );
        CREATE TABLE localized_names (
            localized_name_id INTEGER PRIMARY KEY,
            plant_id INTEGER NOT NULL,
            name_type_id INTEGER NOT NULL,
            locale_code TEXT NOT NULL,
            value TEXT NOT NULL
        );
        CREATE TABLE name_types (
            name_type_id INTEGER PRIMARY KEY,
            name_type TEXT NOT NULL UNIQUE
        );
        CREATE TABLE plant_texts (
            plant_text_id INTEGER PRIMARY KEY,
            plant_id INTEGER NOT NULL,
            region_code TEXT,
            locale_code TEXT NOT NULL,
            field_type TEXT NOT NULL,
            text_value TEXT NOT NULL
        );
        CREATE TABLE synonyms (
            synonym_id INTEGER PRIMARY KEY,
            plant_id INTEGER NOT NULL,
            synonym TEXT NOT NULL
        );
        """
}
