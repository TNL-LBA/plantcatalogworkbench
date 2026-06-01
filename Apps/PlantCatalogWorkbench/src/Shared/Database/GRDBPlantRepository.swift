//
//  GRDBPlantRepository.swift
//  GRDB-backed plant query repository.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation
import GRDB
import OSLog

final class GRDBPlantRepository: PlantRepository, @unchecked Sendable {
    private let databaseQueue: DatabaseQueue
    private let logger = Logger(
        subsystem: "nl.tientijd.PlantCatalogWorkbench",
        category: "GRDBPlantRepository"
    )

    /// Opens a read-only plant repository for a workspace catalog.
    /// - Parameter catalogURL: URL of the workspace SQLite catalog.
    /// - Returns: Initialized repository.
    /// - Throws: GRDB errors when the SQLite database cannot be opened.
    /// - Side Effects: Opens a SQLite connection.
    init(catalogURL: URL) throws {
        var configuration = Configuration()
        configuration.readonly = true
        self.databaseQueue = try DatabaseQueue(path: catalogURL.path(percentEncoded: false), configuration: configuration)
    }

    /// Fetches one page of plant rows for the supplied query.
    /// - Parameters:
    ///   - query: Base plant query.
    ///   - limit: Maximum number of rows to fetch.
    ///   - offset: Offset for infinite scrolling.
    /// - Returns: Page containing rows, total count, and SQL preview.
    /// - Throws: GRDB or SQL validation errors.
    /// - Side Effects: Reads from SQLite.
    func fetchPage(query: PlantQuery, limit: Int, offset: Int) async throws -> PlantQueryPage {
        let boundedLimit = min(max(limit, 1), 250)
        let boundedOffset = max(offset, 0)
        let orderedSQL = """
            \(query.sql)
            ORDER BY \(query.sortDescriptor.column.rawValue) \(query.sortDescriptor.direction.rawValue)
            LIMIT \(boundedLimit) OFFSET \(boundedOffset)
            """
        let validatedSQL = try PlantSQLGuard.validate(sql: orderedSQL, maximumLimit: boundedLimit)
        let preview = SQLPreview(
            sql: validatedSQL,
            parameters: query.parameters,
            pageSize: boundedLimit,
            offset: boundedOffset,
            warning: nil
        )

        logger.debug("fetchPage limit=\(boundedLimit) offset=\(boundedOffset)")

        return try await databaseQueue.read { database in
            let databaseRows = try Row.fetchAll(
                database,
                sql: validatedSQL,
                arguments: statementArguments(from: query.parameters)
            )
            let rows = databaseRows.map(Self.makePlantRow(row:))
            let count = try Int.fetchOne(
                database,
                sql: query.countSQL,
                arguments: statementArguments(from: query.parameters)
            ) ?? rows.count

            return PlantQueryPage(rows: rows, totalCount: count, sqlPreview: preview)
        }
    }

    /// Creates a safe default query from a plain text filter.
    /// - Parameter filterText: Text entered by the user.
    /// - Returns: Query that searches common plant-name columns.
    /// - Throws: Never.
    /// - Side Effects: None.
    func makeDefaultQuery(filterText: String) throws -> PlantQuery {
        let trimmedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilter.isEmpty else {
            return .empty
        }

        let parameter = SQLParameter(value: "%\(trimmedFilter)%")
        let whereClause = """
            WHERE botanical_name LIKE ?
               OR botanical_genus LIKE ?
               OR botanical_species LIKE ?
               OR family_name LIKE ?
               OR page_variant LIKE ?
            """
        return PlantQuery(
            sql: """
                SELECT plant_id, botanical_name, botanical_genus, botanical_species, family_name, page_variant
                FROM plants
                \(whereClause)
                """,
            countSQL: """
                SELECT COUNT(*)
                FROM plants
                \(whereClause)
                """,
            parameters: [parameter, parameter, parameter, parameter, parameter],
            sortDescriptor: PlantSortDescriptor(column: .botanicalName, direction: .ascending)
        )
    }

    /// Executes a bounded read-only query for Foundation Models tool calling.
    /// - Parameters:
    ///   - sql: Model-proposed SQL query.
    ///   - parameters: Bound string parameters.
    ///   - limit: Maximum allowed LIMIT.
    /// - Returns: Compact JSON string with query rows.
    /// - Throws: SQL validation or GRDB errors.
    /// - Side Effects: Reads from SQLite.
    func executeReadOnlyQuery(sql: String, parameters: [SQLParameter], limit: Int) async throws -> String {
        let validatedSQL = try PlantSQLGuard.validate(sql: sql, maximumLimit: limit)
        logger.debug("executeReadOnlyQuery limit=\(limit)")

        return try await databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: validatedSQL,
                arguments: statementArguments(from: parameters)
            )
            let dictionaries = rows.map(Self.makeDictionary(row:))
            let data = try JSONSerialization.data(withJSONObject: dictionaries, options: [.sortedKeys])
            return String(bytes: data, encoding: .utf8) ?? "[]"
        }
    }

    /// Converts SQL parameters into GRDB statement arguments.
    /// - Parameter parameters: App-level SQL parameters.
    /// - Returns: GRDB statement arguments.
    /// - Throws: Never.
    /// - Side Effects: None.
    private func statementArguments(from parameters: [SQLParameter]) -> StatementArguments {
        StatementArguments(parameters.map(\.value))
    }

    /// Maps a database row into the table read model.
    /// - Parameter row: GRDB row from the plants query.
    /// - Returns: Plant table row.
    /// - Throws: Never.
    /// - Side Effects: None.
    private static func makePlantRow(row: Row) -> PlantRow {
        PlantRow(
            plantID: row["plant_id"],
            botanicalName: row["botanical_name"],
            botanicalGenus: row["botanical_genus"],
            botanicalSpecies: row["botanical_species"],
            familyName: row["family_name"],
            pageVariant: row["page_variant"]
        )
    }

    /// Converts a GRDB row into a JSON-compatible dictionary for tool output.
    /// - Parameter row: GRDB row.
    /// - Returns: JSON-compatible dictionary.
    /// - Throws: Never.
    /// - Side Effects: None.
    private static func makeDictionary(row: Row) -> [String: String] {
        row.columnNames.reduce(into: [:]) { partialResult, columnName in
            let value: DatabaseValue = row[columnName]
            partialResult[columnName] = value.description
        }
    }
}
