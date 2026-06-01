//
//  WorkspaceManager.swift
//  Workspace filesystem and SQLite validation services.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation
import OSLog
import SQLite3

@MainActor
final class WorkspaceManager {
    private static let logger = Logger(
        subsystem: "nl.tientijd.PlantCatalogWorkbench",
        category: "WorkspaceManager"
    )

    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    enum WorkspaceError: Equatable, LocalizedError {
        case invalidWorkspaceName
        case missingCatalogFile
        case invalidCatalogDatabase
        case missingDatabaseSchemaVersionsTable
        case missingDatabaseSchemaVersion
        case unsupportedDatabaseSchemaVersion(String)
        case databaseSchemaMismatch(String)
        case missingWorkspaceMetadata
        case missingCatalogDatabase

        var errorDescription: String? {
            switch self {
            case .invalidWorkspaceName:
                return "Enter a workspace name before creating a workspace."
            case .missingCatalogFile:
                return "The selected input database could not be found."
            case .invalidCatalogDatabase:
                return "The selected file is not a readable SQLite database."
            case .missingDatabaseSchemaVersionsTable:
                return "The selected database must contain a `database_schema_versions` table."
            case .missingDatabaseSchemaVersion:
                return "The selected database does not contain a current schema version."
            case let .unsupportedDatabaseSchemaVersion(version):
                return "Database schema version `\(version)` is not supported by this app."
            case let .databaseSchemaMismatch(message):
                return message
            case .missingWorkspaceMetadata:
                return "The selected folder is not a valid Plant Catalog Workbench workspace."
            case .missingCatalogDatabase:
                return "The workspace does not contain a catalog_working.sqlite database."
            }
        }
    }

    private enum Constants {
        static let applicationSupportFolderName = "PlantCatalogWorkbench"
        static let workspaceRootFolderName = "Workspaces"
        static let catalogFilename = "catalog_working.sqlite"
        static let metadataFilename = "workspace-metadata.json"
        static let auditFolderName = "audit"
        static let exportsFolderName = "exports"
    }

    private struct DatabaseSchema {
        let version: String
        let requiredTables: [String: Set<String>]
    }

    private static let supportedSchemas = [
        DatabaseSchema(
            version: "1",
            requiredTables: [
                "database_schema_versions": [
                    "id",
                    "schema_version",
                    "applied_at",
                    "description"
                ],
                "plants": [
                    "plant_id",
                    "botanical_name",
                    "botanical_genus",
                    "botanical_species",
                    "botanical_infraspecific_rank",
                    "botanical_infraspecific_epithet",
                    "botanical_hybrid_marker",
                    "botanical_cultivar_group",
                    "botanical_cultivar_name",
                    "botanical_trade_designation",
                    "botanical_qualifiers_text",
                    "botanical_authority",
                    "botanical_unparsed_remainder",
                    "family_name",
                    "genus_name",
                    "page_variant"
                ],
                "attribute_types": [
                    "attribute_type_id",
                    "attribute_type",
                    "value_kind",
                    "is_multi_value"
                ],
                "attributes": [
                    "attribute_id",
                    "plant_id",
                    "attribute_type_id",
                    "region_code",
                    "value_text",
                    "value_integer",
                    "value_boolean",
                    "value_json"
                ],
                "localized_names": [
                    "localized_name_id",
                    "plant_id",
                    "name_type_id",
                    "locale_code",
                    "value"
                ],
                "name_types": [
                    "name_type_id",
                    "name_type"
                ],
                "plant_texts": [
                    "plant_text_id",
                    "plant_id",
                    "region_code",
                    "locale_code",
                    "field_type",
                    "text_value"
                ],
                "synonyms": [
                    "synonym_id",
                    "plant_id",
                    "synonym"
                ]
            ]
        )
    ]

    private let fileManager: FileManager
    private let workspaceRootURL: URL
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        workspaceRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.workspaceRootURL = workspaceRootURL ?? Self.defaultWorkspaceRoot(fileManager: fileManager)

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        jsonEncoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = jsonEncoder

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = jsonDecoder
    }

    var workspaceRootDirectoryURL: URL {
        workspaceRootURL
    }

    func listWorkspaces() throws -> [WorkspaceSummary] {
        log("listWorkspaces: root=\(workspaceRootURL.path(percentEncoded: false))")

        guard fileManager.fileExists(atPath: filePath(workspaceRootURL)) else {
            log("listWorkspaces: root does not exist, returning 0 workspaces")
            return []
        }

        let directoryURLs: [URL]
        do {
            directoryURLs = try fileManager.contentsOfDirectory(
                at: workspaceRootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            log("listWorkspaces: initial folder read returned \(directoryURLs.count) entries")
        } catch {
            log("listWorkspaces: failed to read root folder: \(error)")
            throw error
        }

        var summaries: [WorkspaceSummary] = []
        for directoryURL in directoryURLs {
            let path = directoryURL.path(percentEncoded: false)
            log("listWorkspaces: inspecting entry=\(path)")

            let isDirectory: Bool
            do {
                let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
                isDirectory = values.isDirectory == true
                log("listWorkspaces: isDirectory=\(isDirectory) for \(path)")
            } catch {
                log("listWorkspaces: failed isDirectory check for \(path): \(error)")
                continue
            }

            guard isDirectory else {
                log("listWorkspaces: skipping non-directory entry=\(path)")
                continue
            }

            do {
                let summary = try openWorkspace(at: directoryURL)
                log("listWorkspaces: accepted workspace id=\(summary.id) name=\(summary.displayName)")
                summaries.append(summary)
            } catch {
                log("listWorkspaces: rejected workspace folder \(path): \(error)")
            }
        }

        let sortedSummaries = summaries
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        log("listWorkspaces: returning \(sortedSummaries.count) workspaces")
        return sortedSummaries
    }

    func createWorkspace(named displayName: String, fromCatalogAt catalogURL: URL) throws -> WorkspaceSummary {
        log("createWorkspace: requested name=\(displayName), catalog=\(catalogURL.path(percentEncoded: false))")

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            log("createWorkspace: invalid empty workspace name")
            throw WorkspaceError.invalidWorkspaceName
        }

        guard fileManager.fileExists(atPath: filePath(catalogURL)) else {
            log("createWorkspace: missing catalog file at \(catalogURL.path(percentEncoded: false))")
            throw WorkspaceError.missingCatalogFile
        }

        try validateCatalogDatabase(at: catalogURL)

        try fileManager.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)

        let metadata = WorkspaceMetadata(
            id: UUID(),
            displayName: trimmedName,
            createdAt: Date(),
            sourceCatalogFilename: catalogURL.lastPathComponent
        )
        let workspaceURL = workspaceRootURL.appendingPathComponent(folderName(for: metadata), isDirectory: true)
        let auditURL = workspaceURL.appendingPathComponent(Constants.auditFolderName, isDirectory: true)
        let exportsURL = workspaceURL.appendingPathComponent(Constants.exportsFolderName, isDirectory: true)
        let copiedCatalogURL = workspaceURL.appendingPathComponent(Constants.catalogFilename)
        let metadataURL = workspaceURL.appendingPathComponent(Constants.metadataFilename)

        do {
            try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: false)
            try fileManager.createDirectory(at: auditURL, withIntermediateDirectories: false)
            try fileManager.createDirectory(at: exportsURL, withIntermediateDirectories: false)

            let data = try jsonEncoder.encode(metadata)
            try data.write(to: metadataURL)

            try fileManager.copyItem(at: catalogURL, to: copiedCatalogURL)
        } catch {
            log("createWorkspace: failed while creating workspace at \(workspaceURL.path(percentEncoded: false)): \(error)")
            try? fileManager.removeItem(at: workspaceURL)
            throw error
        }

        log("createWorkspace: created workspace id=\(metadata.id) path=\(workspaceURL.path(percentEncoded: false))")
        return WorkspaceSummary(
            id: metadata.id,
            displayName: metadata.displayName,
            workspaceURL: workspaceURL,
            catalogURL: copiedCatalogURL,
            auditDirectoryURL: auditURL,
            sourceCatalogFilename: metadata.sourceCatalogFilename,
            createdAt: metadata.createdAt,
            workspaceDescription: metadata.workspaceDescription,
            parseRunCount: 0
        )
    }

    func openWorkspace(at workspaceURL: URL) throws -> WorkspaceSummary {
        log("openWorkspace: opening \(workspaceURL.path(percentEncoded: false))")

        let metadataURL = workspaceURL.appendingPathComponent(Constants.metadataFilename)
        let catalogURL = workspaceURL.appendingPathComponent(Constants.catalogFilename)
        let auditURL = workspaceURL.appendingPathComponent(Constants.auditFolderName, isDirectory: true)

        let metadataExists = fileManager.fileExists(atPath: filePath(metadataURL))
        log("openWorkspace: metadata exists=\(metadataExists) path=\(metadataURL.path(percentEncoded: false))")
        guard metadataExists else {
            log("openWorkspace: missing metadata for \(workspaceURL.path(percentEncoded: false))")
            throw WorkspaceError.missingWorkspaceMetadata
        }

        let catalogExists = fileManager.fileExists(atPath: filePath(catalogURL))
        log("openWorkspace: catalog exists=\(catalogExists) path=\(catalogURL.path(percentEncoded: false))")
        guard catalogExists else {
            log("openWorkspace: missing catalog for \(workspaceURL.path(percentEncoded: false))")
            throw WorkspaceError.missingCatalogDatabase
        }

        let metadataData: Data
        do {
            metadataData = try Data(contentsOf: metadataURL)
            log("openWorkspace: read metadata bytes=\(metadataData.count)")
        } catch {
            log("openWorkspace: failed reading metadata: \(error)")
            throw error
        }

        let metadata: WorkspaceMetadata
        do {
            metadata = try jsonDecoder.decode(WorkspaceMetadata.self, from: metadataData)
            log("openWorkspace: decoded metadata id=\(metadata.id) name=\(metadata.displayName)")
        } catch {
            log("openWorkspace: failed decoding metadata: \(error)")
            throw error
        }

        let runCount: Int
        do {
            runCount = try parseRunCount(in: auditURL)
            log("openWorkspace: parseRunCount=\(runCount)")
        } catch {
            log("openWorkspace: failed counting parse runs: \(error)")
            throw error
        }

        return WorkspaceSummary(
            id: metadata.id,
            displayName: metadata.displayName,
            workspaceURL: workspaceURL,
            catalogURL: catalogURL,
            auditDirectoryURL: auditURL,
            sourceCatalogFilename: metadata.sourceCatalogFilename,
            createdAt: metadata.createdAt,
            workspaceDescription: metadata.workspaceDescription,
            parseRunCount: runCount
        )
    }

    func updateWorkspaceDescription(
        for workspace: WorkspaceSummary,
        to description: String
    ) throws -> WorkspaceSummary {
        let metadataURL = workspace.workspaceURL.appendingPathComponent(Constants.metadataFilename)
        log("updateWorkspaceDescription: workspace=\(workspace.id) metadata=\(metadataURL.path(percentEncoded: false))")

        guard fileManager.fileExists(atPath: filePath(metadataURL)) else {
            log("updateWorkspaceDescription: missing metadata")
            throw WorkspaceError.missingWorkspaceMetadata
        }

        let metadataData: Data
        do {
            metadataData = try Data(contentsOf: metadataURL)
        } catch {
            log("updateWorkspaceDescription: failed reading metadata: \(error)")
            throw error
        }

        var metadata: WorkspaceMetadata
        do {
            metadata = try jsonDecoder.decode(WorkspaceMetadata.self, from: metadataData)
        } catch {
            log("updateWorkspaceDescription: failed decoding metadata: \(error)")
            throw error
        }

        metadata.workspaceDescription = description

        let updatedData = try jsonEncoder.encode(metadata)
        do {
            try updatedData.write(to: metadataURL)
            log("updateWorkspaceDescription: saved description bytes=\(updatedData.count)")
        } catch {
            log("updateWorkspaceDescription: failed writing metadata: \(error)")
            throw error
        }

        return try openWorkspace(at: workspace.workspaceURL)
    }

    private func folderName(for metadata: WorkspaceMetadata) -> String {
        let baseName = metadata.displayName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let safeBaseName = baseName.isEmpty ? "workspace" : baseName
        return "\(safeBaseName)-\(metadata.id.uuidString.lowercased())"
    }

    private func parseRunCount(in auditURL: URL) throws -> Int {
        guard fileManager.fileExists(atPath: filePath(auditURL)) else {
            log("parseRunCount: audit folder missing, count=0 path=\(auditURL.path(percentEncoded: false))")
            return 0
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: auditURL,
                includingPropertiesForKeys: nil
            )
            let count = contents.filter { $0.pathExtension.lowercased() == "json" }.count
            log("parseRunCount: audit entries=\(contents.count), jsonCount=\(count)")
            return count
        } catch {
            log("parseRunCount: failed reading audit folder: \(error)")
            throw error
        }
    }

    private func validateCatalogDatabase(at url: URL) throws {
        log("validateCatalogDatabase: opening \(url.path(percentEncoded: false))")
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(filePath(url), &database, SQLITE_OPEN_READONLY, nil)

        guard openResult == SQLITE_OK, let database else {
            log("validateCatalogDatabase: sqlite open failed result=\(openResult)")
            sqlite3_close(database)
            throw WorkspaceError.invalidCatalogDatabase
        }
        defer { sqlite3_close(database) }

        guard try tableExists("database_schema_versions", in: database) else {
            log("validateCatalogDatabase: missing database_schema_versions table")
            throw WorkspaceError.missingDatabaseSchemaVersionsTable
        }

        let schemaVersion = try currentSchemaVersion(in: database)
        log("validateCatalogDatabase: current schema version=\(schemaVersion)")
        guard let schema = Self.supportedSchemas.first(where: { $0.version == schemaVersion }) else {
            log("validateCatalogDatabase: unsupported schema version=\(schemaVersion)")
            throw WorkspaceError.unsupportedDatabaseSchemaVersion(schemaVersion)
        }

        try validateSchema(schema, in: database)
        log("validateCatalogDatabase: schema validation succeeded")
    }

    private func currentSchemaVersion(in database: OpaquePointer) throws -> String {
        let sql = """
            SELECT schema_version
            FROM database_schema_versions
            ORDER BY id DESC
            LIMIT 1;
            """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareResult == SQLITE_OK, let statement else {
            log("currentSchemaVersion: prepare failed result=\(prepareResult)")
            sqlite3_finalize(statement)
            throw WorkspaceError.invalidCatalogDatabase
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            log("currentSchemaVersion: no schema version row, stepResult=\(stepResult)")
            throw WorkspaceError.missingDatabaseSchemaVersion
        }

        guard let versionPointer = sqlite3_column_text(statement, 0) else {
            log("currentSchemaVersion: schema version column was null")
            throw WorkspaceError.missingDatabaseSchemaVersion
        }

        return String(cString: versionPointer)
    }

    private func validateSchema(_ schema: DatabaseSchema, in database: OpaquePointer) throws {
        for (tableName, requiredColumns) in schema.requiredTables {
            guard try tableExists(tableName, in: database) else {
                log("validateSchema: missing table=\(tableName)")
                throw WorkspaceError.databaseSchemaMismatch(
                    "Database schema version `\(schema.version)` is missing table `\(tableName)`."
                )
            }

            let existingColumns = try columnNames(in: tableName, database: database)
            let missingColumns = requiredColumns.subtracting(existingColumns).sorted()
            guard missingColumns.isEmpty else {
                let missingColumnsDescription = missingColumns.joined(separator: ", ")
                log("validateSchema: table=\(tableName) missingColumns=\(missingColumnsDescription)")
                throw WorkspaceError.databaseSchemaMismatch(
                    "Database schema version `\(schema.version)` table `\(tableName)` is missing columns: \(missingColumnsDescription)."
                )
            }
            log("validateSchema: table=\(tableName) columns ok")
        }
    }

    private func tableExists(_ tableName: String, in database: OpaquePointer) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareResult == SQLITE_OK, let statement else {
            log("tableExists: prepare failed for table=\(tableName), result=\(prepareResult)")
            sqlite3_finalize(statement)
            throw WorkspaceError.invalidCatalogDatabase
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, tableName, -1, sqliteTransient)
        let exists = sqlite3_step(statement) == SQLITE_ROW
        log("tableExists: table=\(tableName), exists=\(exists)")
        return exists
    }

    private func columnNames(in tableName: String, database: OpaquePointer) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareResult == SQLITE_OK, let statement else {
            log("columnNames: prepare failed for table=\(tableName), result=\(prepareResult)")
            sqlite3_finalize(statement)
            throw WorkspaceError.invalidCatalogDatabase
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePointer = sqlite3_column_text(statement, 1) else {
                continue
            }
            columns.insert(String(cString: namePointer))
        }

        return columns
    }

    private func log(_ message: String) {
        Self.logger.debug("\(message, privacy: .public)")
    }

    private func filePath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    private static func defaultWorkspaceRoot(fileManager: FileManager) -> URL {
        let baseDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

        return baseDirectoryURL
            .appendingPathComponent(Constants.applicationSupportFolderName, isDirectory: true)
            .appendingPathComponent(Constants.workspaceRootFolderName, isDirectory: true)
    }
}
