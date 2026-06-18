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
            HStack(alignment: .center, spacing: 10) {
                // The big editable time: large serif hour/minute, each adjustable via its
                // own stepper — keeps the prominent display the reader liked, but editable
                // (the compact `.field` picker rendered far too small).
                TimeUnitStepper(value: hourBinding, range: 0 ... 23)
                Text(":")
                    .font(DaybriefTheme.serifDisplay(40))
                    .foregroundStyle(DaybriefTheme.ink)
                TimeUnitStepper(value: minuteBinding, range: 0 ... 59)
            }
            .frame(maxWidth: .infinity, alignment: .center)
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

    /// Reads/writes the brief hour, committing through the model.
    private var hourBinding: Binding<Int> {
        Binding(get: { model.briefTime.hour }, set: { commit(hour: $0, minute: model.briefTime.minute) })
    }

    /// Reads/writes the brief minute, committing through the model.
    private var minuteBinding: Binding<Int> {
        Binding(get: { model.briefTime.minute }, set: { commit(hour: model.briefTime.hour, minute: $0) })
    }

    /// Persists a new fire-time and reflects it immediately.
    private func commit(hour: Int, minute: Int) {
        let time = FireTime(hour: hour, minute: minute)
        model.briefTime = time
        Task { await model.setBriefTime(time) }
    }
}

/// A large serif time unit (hour or minute) with a stepper, so the prominent time
/// display is also editable. Renders zero-padded ("07", "05") and clamps to `range`.
private struct TimeUnitStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "%02d", value))
                .font(DaybriefTheme.serifDisplay(40))
                .monospacedDigit()
                .foregroundStyle(DaybriefTheme.ink)
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}
