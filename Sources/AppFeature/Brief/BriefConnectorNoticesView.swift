import BriefRender
import DaybriefCore
import SwiftUI

/// A subtle, non-alarming footnote listing any connectors that could not be
/// reached while assembling the brief — phrased editorially ("Slack didn't
/// respond") rather than as an error dump. One dead connector never breaks the
/// page; it just gets a quiet line at the foot of the edition.
struct BriefConnectorNoticesView: View {
    /// The surfaced connector failures, in display order.
    let errors: [BriefViewModel.ConnectorError]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(errors) { error in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 9))
                        .foregroundStyle(DaybriefTheme.inkSecondary.opacity(0.7))
                    Text(notice(for: error))
                        .font(DaybriefTheme.serifItalic(11))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Turns a connector failure into a one-liner. For auth/network/other we surface the
    /// connector's actual (already-redacted, actionable) message — e.g. "Slack is missing
    /// a permission…", "The Gmail API isn't enabled…" — rather than a vague "access has
    /// lapsed," which was misleading for setup/scope problems. Timeouts stay calm.
    private func notice(for error: BriefViewModel.ConnectorError) -> String {
        let name = error.connectorDisplay
        switch error.kind {
        case .timeout:
            return "\(name) didn't respond in time, so it sat this edition out."
        case .auth:
            return cleaned(error.message) ?? "\(name) needs to be reconnected — its access has lapsed."
        case .network:
            return cleaned(error.message) ?? "Couldn't reach \(name) just now."
        case .decode:
            return "\(name) replied in a shape we didn't expect."
        case .other:
            return cleaned(error.message) ?? "\(name) was unavailable for this brief."
        }
    }

    /// Strips the technical `displayMessage` lead-ins so the actionable reason reads
    /// cleanly in the footer; returns `nil` when there's no useful message.
    private func cleaned(_ message: String) -> String? {
        var text = message.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        for prefix in ["Authentication failed: ", "Network error: "] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        if let range = text.range(of: #"^Network error \(HTTP \d+\): "#, options: .regularExpression) {
            text = String(text[range.upperBound...])
        }
        return text.isEmpty ? nil : text
    }
}
