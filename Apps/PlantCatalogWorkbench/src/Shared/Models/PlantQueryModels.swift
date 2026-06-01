//
//  PlantQueryModels.swift
//  Plant query read models and filter state.
//  Plant Catalog Workbench
//
//  Created by <#Author#> on <#Date#>.
//  Copyright (c) <#Year#> <#Organization#>. All rights reserved.
//

import Foundation

struct PlantRow: Identifiable, Equatable, Sendable {
    let plantID: Int64
    let botanicalName: String
    let botanicalGenus: String?
    let botanicalSpecies: String?
    let familyName: String?
    let pageVariant: String?

    var id: Int64 {
        plantID
    }
}

struct PlantSortDescriptor: Equatable, Sendable {
    enum Column: String, CaseIterable, Sendable {
        case botanicalName = "botanical_name"
        case familyName = "family_name"
        case plantID = "plant_id"
    }

    enum Direction: String, Sendable {
        case ascending = "ASC"
        case descending = "DESC"
    }

    let column: Column
    let direction: Direction
}

struct SQLParameter: Equatable, Sendable, CustomStringConvertible {
    let value: String

    var description: String {
        "'\(value)'"
    }
}

struct SQLPreview: Equatable, Sendable {
    let sql: String
    let parameters: [SQLParameter]
    let pageSize: Int
    let offset: Int
    let warning: String?
}

struct PlantQuery: Equatable, Sendable {
    let sql: String
    let countSQL: String
    let parameters: [SQLParameter]
    let sortDescriptor: PlantSortDescriptor

    static let empty = Self(
        sql: """
            SELECT plant_id, botanical_name, botanical_genus, botanical_species, family_name, page_variant
            FROM plants
            """,
        countSQL: "SELECT COUNT(*) FROM plants",
        parameters: [],
        sortDescriptor: PlantSortDescriptor(column: .botanicalName, direction: .ascending)
    )
}

struct PlantQueryPage: Equatable, Sendable {
    let rows: [PlantRow]
    let totalCount: Int
    let sqlPreview: SQLPreview
}

enum PlantFilterState: Equatable, Sendable {
    case idle
    case resolving
    case modelUnavailable(String)
    case ready(PlantQuery)
    case failed(String)
}

protocol PlantRepository: Sendable {
    func fetchPage(query: PlantQuery, limit: Int, offset: Int) async throws -> PlantQueryPage
    func makeDefaultQuery(filterText: String) throws -> PlantQuery
    func executeReadOnlyQuery(sql: String, parameters: [SQLParameter], limit: Int) async throws -> String
}

protocol PlantFilterModelServicing: Sendable {
    func resolveFilter(_ filterText: String, repository: PlantRepository) async -> PlantFilterState
}
