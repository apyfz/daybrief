import DaybriefCore
import Foundation
import GRDB

/// GRDB row for the `briefs` table. The `sections` and `connectorErrors` value
/// trees are stored as JSON text columns (see ``Migrations`` for the rationale).
struct BriefRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "briefs"

    var id: String
    var generatedAt: Date
    var spaceFilter: String?
    var sectionsJSON: String
    var connectorErrorsJSON: String

    enum CodingKeys: String, CodingKey {
        case id
        case generatedAt = "generated_at"
        case spaceFilter = "space_filter"
        case sectionsJSON = "sections_json"
        case connectorErrorsJSON = "connector_errors_json"
    }
}

extension BriefRecord {
    /// Builds a row from a ``Brief``, serializing the nested value trees to JSON.
    init(_ brief: Brief) throws {
        id = brief.id.uuidString
        generatedAt = brief.generatedAt
        spaceFilter = brief.spaceFilter
        sectionsJSON = try JSONColumn.encode(brief.sections)
        connectorErrorsJSON = try JSONColumn.encode(brief.connectorErrors)
    }

    /// Maps the row back to a ``Brief``, decoding the JSON columns.
    func toCore() throws -> Brief {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.corruptRow(entity: "Brief", detail: "invalid UUID '\(id)'")
        }
        let sections = try JSONColumn.decode([BriefSection].self, from: sectionsJSON, entity: "Brief.sections")
        let errors = try JSONColumn.decode(
            [ConnectorErrorSummary].self,
            from: connectorErrorsJSON,
            entity: "Brief.connectorErrors"
        )
        return Brief(
            id: uuid,
            generatedAt: generatedAt,
            spaceFilter: spaceFilter,
            sections: sections,
            connectorErrors: errors
        )
    }
}
