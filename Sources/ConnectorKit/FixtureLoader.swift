import DaybriefCore
import Foundation

/// Loads on-disk JSON fixtures for connector tests.
///
/// Connector tests record real provider responses once under `Tests/Fixtures/<id>/*.json`
/// and replay them — `normalize(_:)` is tested directly against the parsed JSON, and
/// `fetch(_:)` is tested by feeding the same bytes through ``DaybriefCore/MockHTTPTransport``.
/// This loader resolves the shared `Tests/Fixtures` directory from the package source
/// tree (via `#filePath`), so it works without declaring SPM resource bundles per target.
///
/// Public so every per-connector test target can reuse one harness.
public struct FixtureLoader: Sendable {
    /// The connector id whose fixture subdirectory this loader reads.
    public let connectorId: ConnectorID
    /// The root `Tests/Fixtures` directory.
    public let fixturesRoot: URL

    /// Errors thrown while loading fixtures.
    public enum FixtureError: Error, Sendable, Equatable {
        /// No file named `<name>.json` exists in the connector's fixture directory.
        case notFound(connectorId: String, name: String, searched: String)
        /// The fixture bytes were not valid JSON.
        case malformed(name: String)
    }

    /// Creates a loader for `connectorId`.
    ///
    /// - Parameters:
    ///   - connectorId: The connector whose fixtures to load (subdirectory name).
    ///   - fixturesRoot: The `Tests/Fixtures` directory; defaults to the location
    ///     resolved from this file's path in the package source tree.
    public init(connectorId: ConnectorID, fixturesRoot: URL? = nil) {
        self.connectorId = connectorId
        self.fixturesRoot = fixturesRoot ?? Self.defaultFixturesRoot()
    }

    /// The directory holding this connector's fixtures (`Tests/Fixtures/<id>`).
    public var connectorDirectory: URL {
        fixturesRoot.appendingPathComponent(connectorId.rawValue, isDirectory: true)
    }

    /// Loads the raw bytes of `<name>.json` from the connector's fixture directory.
    ///
    /// `name` may be given with or without the `.json` extension.
    public func data(_ name: String) throws -> Data {
        let fileName = name.hasSuffix(".json") ? name : "\(name).json"
        let url = connectorDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else {
            throw FixtureError.notFound(
                connectorId: connectorId.rawValue,
                name: fileName,
                searched: connectorDirectory.path
            )
        }
        return data
    }

    /// Loads `<name>.json` as a ``DaybriefCore/JSONValue``.
    public func json(_ name: String) throws -> JSONValue {
        let data = try data(name)
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw FixtureError.malformed(name: name)
        }
    }

    /// Loads `<name>.json` and decodes it as `type`.
    public func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let data = try data(name)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FixtureError.malformed(name: name)
        }
    }

    /// Resolves `Tests/Fixtures` from this source file's location at compile time.
    ///
    /// `#filePath` points at `…/Sources/ConnectorKit/FixtureLoader.swift`; walking up to
    /// the package root and into `Tests/Fixtures` gives the shared fixture directory.
    private static func defaultFixturesRoot() -> URL {
        // …/Sources/ConnectorKit/FixtureLoader.swift → packageRoot/Tests/Fixtures
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent() // ConnectorKit
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // packageRoot
        return packageRoot
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
    }
}
