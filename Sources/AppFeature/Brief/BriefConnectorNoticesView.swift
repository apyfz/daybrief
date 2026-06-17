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
                        .font(DaybriefTheme.serifBody(11).italic())
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Turns a connector failure into a calm, editorial one-liner.
    private func notice(for error: BriefViewModel.ConnectorError) -> String {
        let name = error.connectorDisplay
        switch error.kind {
        case .timeout:
            return "\(name) didn't respond in time, so it sat this edition out."
        case .auth:
            return "\(name) needs to be reconnected — its access has lapsed."
        case .network:
            return "Couldn't reach \(name) just now."
        case .decode:
            return "\(name) replied in a shape we didn't expect."
        case .other:
            return "\(name) was unavailable for this brief."
        }
    }
}
