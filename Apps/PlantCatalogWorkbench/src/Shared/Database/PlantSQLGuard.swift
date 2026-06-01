//
//  PlantSQLGuard.swift
//  Read-only SQL validation for plant list model tools.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation

enum PlantSQLGuard {
    enum SQLGuardError: Equatable, LocalizedError {
        case emptySQL
        case multipleStatements
        case unsupportedStatement
        case forbiddenToken(String)
        case missingLimit
        case limitTooLarge(Int)
        case unknownTable(String)
        case unknownColumn(String)

        var errorDescription: String? {
            switch self {
            case .emptySQL:
                return "The SQL query is empty."
            case .multipleStatements:
                return "Only one read-only SQL statement is allowed."
            case .unsupportedStatement:
                return "Only SELECT or read-only WITH queries are allowed."
            case let .forbiddenToken(token):
                return "The SQL query contains forbidden token `\(token)`."
            case .missingLimit:
                return "The SQL query must include a LIMIT."
            case let .limitTooLarge(limit):
                return "The SQL query LIMIT \(limit) is larger than the allowed page size."
            case let .unknownTable(table):
                return "The SQL query references unknown table `\(table)`."
            case let .unknownColumn(column):
                return "The SQL query references unknown column `\(column)`."
            }
        }
    }

    private static let allowedTables: Set<String> = [
        "plants",
        "localized_names",
        "name_types",
        "attributes",
        "attribute_types",
        "plant_texts",
        "synonyms"
    ]

    private static let allowedColumns: Set<String> = [
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
        "page_variant",
        "localized_name_id",
        "name_type_id",
        "locale_code",
        "value",
        "name_type",
        "attribute_id",
        "attribute_type_id",
        "region_code",
        "value_text",
        "value_integer",
        "value_boolean",
        "value_json",
        "attribute_type",
        "value_kind",
        "is_multi_value",
        "plant_text_id",
        "field_type",
        "text_value",
        "synonym_id",
        "synonym"
    ]

    private static let forbiddenTokens: [String] = [
        "insert",
        "update",
        "delete",
        "drop",
        "alter",
        "create",
        "replace",
        "pragma",
        "attach",
        "detach",
        "vacuum",
        "reindex",
        "temp",
        "temporary"
    ]

    /// Validates model-generated SQL before it reaches SQLite.
    /// - Parameters:
    ///   - sql: SQL text proposed by the model tool.
    ///   - maximumLimit: Largest row limit the app accepts for a single page.
    /// - Returns: Normalized SQL with a trailing semicolon removed.
    /// - Throws: `SQLGuardError` when the query is not an allowed read-only query.
    /// - Side Effects: None.
    static func validate(sql: String, maximumLimit: Int) throws -> String {
        let trimmedSQL = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSQL.isEmpty else {
            throw SQLGuardError.emptySQL
        }

        let semicolonCount = trimmedSQL.filter { $0 == ";" }.count
        guard semicolonCount == 0 || (semicolonCount == 1 && trimmedSQL.hasSuffix(";")) else {
            throw SQLGuardError.multipleStatements
        }

        let normalizedSQL = trimmedSQL.trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let lowercaseSQL = normalizedSQL.lowercased()
        guard lowercaseSQL.hasPrefix("select ") || lowercaseSQL.hasPrefix("with ") else {
            throw SQLGuardError.unsupportedStatement
        }

        try validateForbiddenTokens(in: lowercaseSQL)
        try validateLimit(in: lowercaseSQL, maximumLimit: maximumLimit)
        try validateTables(in: lowercaseSQL)
        try validateColumns(in: lowercaseSQL)

        return normalizedSQL
    }

    /// Finds forbidden SQL keywords in tokenized SQL text.
    /// - Parameter lowercaseSQL: Lowercased SQL string.
    /// - Returns: Nothing.
    /// - Throws: `SQLGuardError.forbiddenToken`.
    /// - Side Effects: None.
    private static func validateForbiddenTokens(in lowercaseSQL: String) throws {
        let tokens = tokenSet(from: lowercaseSQL)
        if let forbiddenToken = forbiddenTokens.first(where: { tokens.contains($0) }) {
            throw SQLGuardError.forbiddenToken(forbiddenToken)
        }
    }

    /// Validates that the query contains a bounded LIMIT.
    /// - Parameters:
    ///   - lowercaseSQL: Lowercased SQL string.
    ///   - maximumLimit: Largest row limit the app accepts for a single page.
    /// - Returns: Nothing.
    /// - Throws: `SQLGuardError.missingLimit` or `SQLGuardError.limitTooLarge`.
    /// - Side Effects: None.
    private static func validateLimit(in lowercaseSQL: String, maximumLimit: Int) throws {
        let pattern = #"\blimit\s+(\d+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(lowercaseSQL.startIndex..<lowercaseSQL.endIndex, in: lowercaseSQL)
        guard let match = regex.firstMatch(in: lowercaseSQL, range: range),
              let limitRange = Range(match.range(at: 1), in: lowercaseSQL),
              let limit = Int(lowercaseSQL[limitRange]) else {
            throw SQLGuardError.missingLimit
        }

        guard limit <= maximumLimit else {
            throw SQLGuardError.limitTooLarge(limit)
        }
    }

    /// Validates table references after FROM and JOIN tokens.
    /// - Parameter lowercaseSQL: Lowercased SQL string.
    /// - Returns: Nothing.
    /// - Throws: `SQLGuardError.unknownTable`.
    /// - Side Effects: None.
    private static func validateTables(in lowercaseSQL: String) throws {
        let tokens = tokenArray(from: lowercaseSQL)
        for index in tokens.indices where tokens[index] == "from" || tokens[index] == "join" {
            let tableIndex = tokens.index(after: index)
            guard tableIndex < tokens.endIndex else {
                continue
            }

            let tableName = tokens[tableIndex]
            guard allowedTables.contains(tableName) else {
                throw SQLGuardError.unknownTable(tableName)
            }
        }
    }

    /// Validates dotted column references in model-generated SQL.
    /// - Parameter lowercaseSQL: Lowercased SQL string.
    /// - Returns: Nothing.
    /// - Throws: `SQLGuardError.unknownColumn`.
    /// - Side Effects: None.
    private static func validateColumns(in lowercaseSQL: String) throws {
        try validateSelectedColumns(in: lowercaseSQL)
        try validatePredicateColumns(in: lowercaseSQL)

        let pattern = #"\b[a-z_][a-z0-9_]*\.([a-z_][a-z0-9_]*)\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(lowercaseSQL.startIndex..<lowercaseSQL.endIndex, in: lowercaseSQL)
        let matches = regex.matches(in: lowercaseSQL, range: range)

        for match in matches {
            guard let columnRange = Range(match.range(at: 1), in: lowercaseSQL) else {
                continue
            }

            let columnName = String(lowercaseSQL[columnRange])
            guard allowedColumns.contains(columnName) else {
                throw SQLGuardError.unknownColumn(columnName)
            }
        }
    }

    /// Validates plain columns in the SELECT list.
    /// - Parameter lowercaseSQL: Lowercased SQL string.
    /// - Returns: Nothing.
    /// - Throws: `SQLGuardError.unknownColumn`.
    /// - Side Effects: None.
    private static func validateSelectedColumns(in lowercaseSQL: String) throws {
        guard let selectRange = lowercaseSQL.range(of: "select "),
              let fromRange = lowercaseSQL.range(of: " from ", range: selectRange.upperBound..<lowercaseSQL.endIndex) else {
            return
        }

        let selectedText = lowercaseSQL[selectRange.upperBound..<fromRange.lowerBound]
        for component in selectedText.split(separator: ",") {
            let token = component
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "." }
                .first
                .map(String.init) ?? ""
            let columnName = token.components(separatedBy: ".").last ?? token

            guard columnName == "*" || columnName == "count" || allowedColumns.contains(columnName) else {
                throw SQLGuardError.unknownColumn(columnName)
            }
        }
    }

    /// Validates plain columns used before common predicate operators.
    /// - Parameter lowercaseSQL: Lowercased SQL string.
    /// - Returns: Nothing.
    /// - Throws: `SQLGuardError.unknownColumn`.
    /// - Side Effects: None.
    private static func validatePredicateColumns(in lowercaseSQL: String) throws {
        let pattern = #"\b(?:(?:[a-z_][a-z0-9_]*)\.)?([a-z_][a-z0-9_]*)\s*(?:=|like|in|>|<|is)\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(lowercaseSQL.startIndex..<lowercaseSQL.endIndex, in: lowercaseSQL)
        let matches = regex.matches(in: lowercaseSQL, range: range)

        for match in matches {
            guard let columnRange = Range(match.range(at: 1), in: lowercaseSQL) else {
                continue
            }

            let columnName = String(lowercaseSQL[columnRange])
            guard allowedColumns.contains(columnName) else {
                throw SQLGuardError.unknownColumn(columnName)
            }
        }
    }

    /// Splits SQL text into lowercased tokens for conservative validation.
    /// - Parameter sql: SQL text.
    /// - Returns: Ordered tokens.
    /// - Throws: Never.
    /// - Side Effects: None.
    private static func tokenArray(from sql: String) -> [String] {
        sql.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Builds a token set for quick keyword lookup.
    /// - Parameter sql: SQL text.
    /// - Returns: Unique tokens.
    /// - Throws: Never.
    /// - Side Effects: None.
    private static func tokenSet(from sql: String) -> Set<String> {
        Set(tokenArray(from: sql))
    }
}
