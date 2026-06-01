//
//  PlantFilterModelService.swift
//  Foundation Models natural-language plant filter service.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation
import FoundationModels
import OSLog

@Generable(description: "A bounded read-only database query the tool may execute.")
struct PlantDatabaseQueryArguments {
    @Guide(description: "A single SELECT statement with a LIMIT of 100 or less.")
    var sql: String

    @Guide(description: "String parameters for placeholders in the same order.")
    var parameters: [String]
}

@Generable(description: "A safe SQL filter for the plant table.")
struct PlantFilterGeneration {
    @Guide(
        description: """
        SELECT plant_id, botanical_name, botanical_genus, botanical_species, family_name, page_variant \
        FROM plants with optional WHERE clauses. Do not include ORDER BY, LIMIT, or OFFSET.
        """
    )
    var sql: String

    @Guide(description: "SELECT COUNT(*) FROM plants with the same WHERE clauses as sql.")
    var countSQL: String

    @Guide(description: "String parameters for placeholders in both SQL statements.")
    var parameters: [String]

    @Guide(description: "One of botanical_name, family_name, plant_id.")
    var sortColumn: String

    @Guide(description: "ASC or DESC.")
    var sortDirection: String
}

final class PlantDatabaseQueryTool: Tool {
    let repository: PlantRepository
    let limit: Int
    let description = """
        Executes one safe, read-only SQLite SELECT query against the plant catalog. Use this to inspect \
        possible matching rows before returning the final filter SQL. Never request writes or schema changes.
        """

    /// Creates a database query tool for Foundation Models.
    /// - Parameters:
    ///   - repository: Plant repository used for read-only query execution.
    ///   - limit: Maximum row limit allowed for tool calls.
    /// - Returns: Initialized tool.
    /// - Throws: Never.
    /// - Side Effects: None.
    init(repository: PlantRepository, limit: Int = 100) {
        self.repository = repository
        self.limit = limit
    }

    /// Executes a read-only model-requested query.
    /// - Parameter arguments: Generated SQL and string parameters.
    /// - Returns: JSON rows from the database.
    /// - Throws: SQL validation, repository, or cancellation errors.
    /// - Side Effects: Reads from SQLite.
    func call(arguments: PlantDatabaseQueryArguments) async throws -> String {
        try Task.checkCancellation()
        let parameters = arguments.parameters.map(SQLParameter.init(value:))
        return try await repository.executeReadOnlyQuery(
            sql: arguments.sql,
            parameters: parameters,
            limit: limit
        )
    }
}

final class PlantFilterModelService: PlantFilterModelServicing, @unchecked Sendable {
    private let logger = Logger(
        subsystem: "nl.tientijd.PlantCatalogWorkbench",
        category: "PlantFilterModelService"
    )
    private let timeoutSeconds: UInt64

    /// Creates a Foundation Models plant filter service.
    /// - Parameter timeoutSeconds: Maximum time allowed for a single model request.
    /// - Returns: Initialized service.
    /// - Throws: Never.
    /// - Side Effects: None.
    init(timeoutSeconds: UInt64 = 12) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// Resolves natural-language filter text into a safe plant query.
    /// - Parameters:
    ///   - filterText: Natural-language filter entered by the user.
    ///   - repository: Repository available to the model tool.
    /// - Returns: Filter state with a query or clear failure.
    /// - Throws: Never.
    /// - Side Effects: May invoke the on-device language model and read from SQLite through a tool.
    func resolveFilter(_ filterText: String, repository: PlantRepository) async -> PlantFilterState {
        let trimmedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilter.isEmpty else {
            return .ready(.empty)
        }

        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            logger.warning("Foundation Models unavailable for plant filter")
            return .modelUnavailable(describeAvailability(model.availability))
        }

        do {
            let generation = try await withTimeout(seconds: timeoutSeconds) {
                try await self.generateFilter(trimmedFilter, model: model, repository: repository)
            }
            return .ready(makePlantQuery(from: generation))
        } catch is CancellationError {
            return .failed("Filter request was cancelled.")
        } catch {
            logger.error("Foundation Models plant filter failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Requests a structured SQL filter from Foundation Models.
    /// - Parameters:
    ///   - filterText: Natural-language filter entered by the user.
    ///   - model: System language model.
    ///   - repository: Repository exposed to the model tool.
    /// - Returns: Generated filter SQL description.
    /// - Throws: Foundation Models or cancellation errors.
    /// - Side Effects: May read from SQLite through the model tool.
    private func generateFilter(
        _ filterText: String,
        model: SystemLanguageModel,
        repository: PlantRepository
    ) async throws -> PlantFilterGeneration {
        let tool = PlantDatabaseQueryTool(repository: repository)
        let session = LanguageModelSession(
            model: model,
            tools: [tool],
            instructions: Self.instructions
        )

        let response = try await session.respond(
            to: """
                Convert this plant filter request into safe SQL for the plant catalog:
                \(filterText)

                Before returning the final filter, call the plant database query tool when the request \
                needs database evidence. Return only a structured filter query.
                """,
            generating: PlantFilterGeneration.self
        )
        return response.content
    }

    /// Converts generated content into an app-level query.
    /// - Parameter generation: Generated SQL filter.
    /// - Returns: Plant query with safe sort defaults.
    /// - Throws: Never.
    /// - Side Effects: None.
    private func makePlantQuery(from generation: PlantFilterGeneration) -> PlantQuery {
        let sortColumn = PlantSortDescriptor.Column(rawValue: generation.sortColumn)
            ?? .botanicalName
        let sortDirection = PlantSortDescriptor.Direction(rawValue: generation.sortDirection.uppercased())
            ?? .ascending

        return PlantQuery(
            sql: generation.sql,
            countSQL: generation.countSQL,
            parameters: generation.parameters.map(SQLParameter.init(value:)),
            sortDescriptor: PlantSortDescriptor(column: sortColumn, direction: sortDirection)
        )
    }

    /// Describes why the system language model is unavailable.
    /// - Parameter availability: Model availability status.
    /// - Returns: User-presentable status.
    /// - Throws: Never.
    /// - Side Effects: None.
    private func describeAvailability(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Foundation Models is available."
        case let .unavailable(reason):
            return "Foundation Models is unavailable: \(reason)."
        }
    }

    /// Runs an async operation with a timeout.
    /// - Parameters:
    ///   - seconds: Timeout in seconds.
    ///   - operation: Async operation to run.
    /// - Returns: Operation result.
    /// - Throws: Operation error or cancellation when the timeout wins.
    /// - Side Effects: Starts child tasks.
    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    private static let instructions = """
        You translate natural-language plant filters into SQLite SELECT queries for a local plant catalog.
        Use only these output columns: plant_id, botanical_name, botanical_genus, botanical_species, \
        family_name, page_variant.
        Use only whitelisted catalog tables and read-only SELECT statements.
        Prefer placeholders with string parameters for user terms.
        Never include ORDER BY, LIMIT, OFFSET, PRAGMA, writes, schema changes, or multiple statements in \
        the final sql or countSQL fields.
        """
}
