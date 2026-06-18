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
    /// The full ``Brief`` encoded as JSON (v2+). The lossless source of truth on read;
    /// `nil` for pre-v2 rows, which fall back to the column-based reconstruction.
    var briefJSON: String?

    enum CodingKeys: String, CodingKey {
        case id
        case generatedAt = "generated_at"
        case spaceFilter = "space_filter"
        case sectionsJSON = "sections_json"
        case connectorErrorsJSON = "connector_errors_json"
        case briefJSON = "brief_json"
    }
}

extension BriefRecord {
    /// Builds a row from a ``Brief``. The whole value is stored in `brief_json` for a
    /// lossless round-trip; the `sections`/`connectorErrors` columns are still written
    /// (back-compat + the indexed `generated_at` drives ordering).
    init(_ brief: Brief) throws {
        id = brief.id.uuidString
        generatedAt = brief.generatedAt
        spaceFilter = brief.spaceFilter
        sectionsJSON = try JSONColumn.encode(brief.sections)
        connectorErrorsJSON = try JSONColumn.encode(brief.connectorErrors)
        briefJSON = try JSONColumn.encode(brief)
    }

    /// Maps the row back to a ``Brief``.
    ///
    /// Prefers the full `brief_json` (v2+), which preserves the masthead, lede, lead,
    /// mood, and hero. Pre-v2 rows have no `brief_json`, so they fall back to the
    /// lossy column reconstruction (masthead/lede/lead/mood/hero default to empty) —
    /// the same behavior those rows had before this change.
    func toCore() throws -> Brief {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.corruptRow(entity: "Brief", detail: "invalid UUID '\(id)'")
        }
        if let briefJSON, !briefJSON.isEmpty {
            return try JSONColumn.decode(Brief.self, from: briefJSON, entity: "Brief")
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
