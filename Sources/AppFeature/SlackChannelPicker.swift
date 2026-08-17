import DaybriefUI
import SlackConnector
import SwiftUI

/// Picks which Slack channels the brief covers — shared by onboarding and Settings so
/// the two can't drift into describing different rules.
///
/// Coverage is **opt-in and capped**. Unread state is per-conversation, so every covered
/// channel costs an API call on every brief; a real workspace (66 channels on the
/// author's account) would blow the fetch budget and bury the Group section in ambient
/// chatter. Picking a handful you actually follow is both faster and a better brief.
///
/// DMs and @-mentions are never part of this choice — they're always covered.
struct SlackChannelPicker: View {
    @Bindable var model: AppModel
    /// Shown above the list. Onboarding and Settings frame the same choice differently.
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.isLoadingSlackChannels {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading channels…")
                        .font(.system(size: 12))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                }
            } else if model.slackChannels.isEmpty {
                Text("No channels found. If you just added the channels:read permission, "
                    + "reconnect Slack with a fresh token.")
                    .font(.system(size: 12))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                channelList
            }
        }
        .task { await model.loadSlackChannels() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.slackChannels.isEmpty {
                HStack(spacing: 6) {
                    Text("\(model.selectedSlackChannelIDs.count) of \(model.maxSlackChannels) selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DaybriefTheme.ink)
                    if !model.canSelectMoreSlackChannels {
                        Text("— uncheck one to swap")
                            .font(.system(size: 11))
                            .foregroundStyle(DaybriefTheme.inkSecondary)
                    }
                }
            }
        }
    }

    private var channelList: some View {
        // Tall workspaces scroll rather than pushing the sheet's actions off-screen.
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.slackChannels) { channel in
                    let isOn = model.selectedSlackChannelIDs.contains(channel.id)
                    Toggle(isOn: binding(for: channel)) {
                        HStack(spacing: 6) {
                            (channel.isPrivate ? DaybriefIcon.lock : DaybriefIcon.hash)
                                .daybriefIcon(size: 11)
                                .foregroundStyle(DaybriefTheme.inkSecondary)
                            Text(channel.name)
                                .font(.system(size: 12))
                                .foregroundStyle(DaybriefTheme.ink)
                        }
                    }
                    .toggleStyle(.checkbox)
                    // At the cap, unpicked channels go quiet rather than failing on click.
                    .disabled(!isOn && !model.canSelectMoreSlackChannels)
                    .opacity(isOn || model.canSelectMoreSlackChannels ? 1 : 0.45)
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private func binding(for channel: SlackConnector.MemberChannel) -> Binding<Bool> {
        Binding(
            get: { model.selectedSlackChannelIDs.contains(channel.id) },
            set: { included in
                Task { await model.setSlackChannel(id: channel.id, included: included) }
            }
        )
    }
}
