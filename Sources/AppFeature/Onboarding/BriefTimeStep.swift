import Pipeline
import SwiftUI

/// Onboarding step 4 (design §14.4): pick the daily fire-time.
///
/// A wheel `DatePicker` (hour + minute only) bound to `model.briefTime` via a
/// `FireTime`↔`Date` bridge; commits through `model.setBriefTime`. Generate-on-wake
/// catch-up is automatic (design §12), so we just reassure the user about it.
struct BriefTimeStep: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                DatePicker(
                    "",
                    selection: timeBinding,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.field)
                .labelsHidden()
                .font(DaybriefTheme.serifBody(18))

                Text(model.briefTime.encoded)
                    .font(DaybriefTheme.serifDisplay(40))
                    .foregroundStyle(DaybriefTheme.ink)
                    .monospacedDigit()
            }
            .padding(18)
            .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DaybriefTheme.ink.opacity(0.1), lineWidth: 1)
            )

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 13))
                    .foregroundStyle(DaybriefTheme.accent)
                Text("If your Mac is asleep at this time, Daybrief writes the brief the moment you wake it or open the app — you never miss a morning.")
                    .font(.system(size: 12))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Bridges the `FireTime` (hour/minute) to the `Date` `DatePicker` expects,
    /// pinning the date portion to today so only the time matters.
    private var timeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                let calendar = Calendar.current
                return calendar.date(
                    bySettingHour: model.briefTime.hour,
                    minute: model.briefTime.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let time = FireTime(hour: parts.hour ?? 7, minute: parts.minute ?? 0)
                model.briefTime = time
                Task { await model.setBriefTime(time) }
            }
        )
    }
}
