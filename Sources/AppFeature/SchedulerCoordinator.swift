import AppKit
import Dispatch
import Foundation
import os
import Pipeline

/// Drives the daily brief on a wall-clock schedule and catches up after sleep
/// (design §12).
///
/// A self-rescheduling one-shot `DispatchSourceTimer` fires at the user's local
/// brief time while the app runs; an `NSWorkspace.didWakeNotification` observer and
/// the launch path both route through ``AppModel/onWakeOrLaunch()`` so a missed
/// fire-time is honored the moment the Mac wakes or the app opens. Generation is
/// wrapped in `beginActivity(.userInitiated)` so App Nap doesn't throttle the timer
/// or network on this accessory app.
@MainActor
public final class SchedulerCoordinator {
    private let model: AppModel
    private var timer: DispatchSourceTimer?
    private var wakeObserver: (any NSObjectProtocol)?
    private static let logger = Logger(subsystem: "co.daybrief.app", category: "SchedulerCoordinator")

    /// Creates a coordinator driving `model`.
    public init(model: AppModel) {
        self.model = model
    }

    /// Starts the scheduler: runs the launch catch-up, registers the wake observer,
    /// and arms the next daily timer.
    public func start() {
        registerWakeObserver()
        Task { @MainActor in
            await self.model.onWakeOrLaunch()
            self.armNextTimer()
        }
    }

    /// Tears down the timer and observer.
    public func stop() {
        timer?.cancel()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Timer

    /// Arms a one-shot timer for the next fire-time, which generates and then
    /// re-arms itself for the following day.
    private func armNextTimer() {
        timer?.cancel()

        let scheduler = BriefScheduler(fireTime: model.briefTime)
        let fireDate = scheduler.nextFireDate(now: Date())
        let interval = max(1, fireDate.timeIntervalSinceNow)

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Self.logger.notice("Daily timer fired")
            self.runGeneration { [weak self] in
                self?.armNextTimer()
            }
        }
        source.resume()
        timer = source
        Self.logger.debug("Armed daily timer in \(interval, privacy: .public)s")
    }

    // MARK: - Wake

    private func registerWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The closure may run off the main actor's static checker's view; hop back.
            MainActor.assumeIsolated {
                guard let self else { return }
                Self.logger.notice("System woke — running catch-up")
                self.runGeneration { [weak self] in
                    self?.armNextTimer()
                }
            }
        }
    }

    // MARK: - Generation wrapper

    /// Runs `onWakeOrLaunch` inside an App-Nap-resistant activity, then re-arms.
    private func runGeneration(then completion: @escaping @MainActor () -> Void) {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Generating the daily brief"
        )
        Task { @MainActor in
            await self.model.onWakeOrLaunch()
            ProcessInfo.processInfo.endActivity(activity)
            completion()
        }
    }
}
