import DaybriefCore
import Foundation

/// The typed error surface for the orchestration layer.
///
/// A connector failure is *never* a `PipelineError` — those are folded into the
/// partial brief as ``DaybriefCore/ConnectorErrorSummary`` values (see
/// ``BriefGenerator``). `PipelineError` is reserved for failures that prevent a
/// brief from being produced at all: an absent model adapter, a synthesis failure
/// the repair layer could not recover, or a persistence failure.
public enum PipelineError: Error, Sendable, Equatable {
    /// No ``LLMKit/ModelAdapter`` was available to synthesize the brief.
    case noModelAdapter
    /// Synthesis failed and could not be recovered. `reason` is a short,
    /// secret-free explanation suitable for display.
    case synthesisFailed(reason: String)
    /// Persisting the generated brief failed. `reason` is a short, secret-free
    /// explanation.
    case persistenceFailed(reason: String)
    /// A requested connector id is not registered. `connectorId` identifies it.
    case unknownConnector(connectorId: ConnectorID)

    /// A short, display-safe message (already redacted of secrets).
    public var displayMessage: String {
        switch self {
        case .noModelAdapter:
            return "No AI model is configured. Add a model in settings to generate a brief."
        case let .synthesisFailed(reason):
            return "The brief could not be written: \(reason)"
        case let .persistenceFailed(reason):
            return "The brief could not be saved: \(reason)"
        case let .unknownConnector(connectorId):
            return "Unknown connector '\(connectorId.rawValue)'."
        }
    }
}
