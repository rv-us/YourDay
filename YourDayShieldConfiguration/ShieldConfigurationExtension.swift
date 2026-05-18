import ManagedSettings
import ManagedSettingsUI
import OSLog
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let logger = Logger(subsystem: "com.yourday.app", category: "ShieldConfiguration")

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        logger.notice("configuration(shielding application:) appName=\(application.localizedDisplayName ?? "unknown", privacy: .public)")
        return makeConfiguration(appName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        let categoryName = String(describing: category.localizedDisplayName)
        logger.notice(
            "configuration(shielding application:in:) appName=\(application.localizedDisplayName ?? "unknown", privacy: .public) category=\(categoryName, privacy: .public)"
        )
        return makeConfiguration(appName: application.localizedDisplayName ?? categoryName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        logger.notice("configuration(shielding webDomain:) domain=\(webDomain.domain ?? "unknown", privacy: .public)")
        return makeConfiguration(appName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        let categoryName = String(describing: category.localizedDisplayName)
        logger.notice(
            "configuration(shielding webDomain:in:) domain=\(webDomain.domain ?? "unknown", privacy: .public) category=\(categoryName, privacy: .public)"
        )
        return makeConfiguration(appName: webDomain.domain ?? categoryName)
    }

    // MARK: - Shared builder

    private func makeConfiguration(appName: String?) -> ShieldConfiguration {
        let snapshot = AppGroupDefaults.loadSnapshot()
        let penaltyAmount = snapshot?.penaltyAmount ?? 100
        let displayApp = appName ?? "this app"
        logger.notice("makeConfiguration start appName=\(displayApp, privacy: .public) penaltyAmount=\(penaltyAmount)")

        guard let snapshot, snapshot.dayKey == ShieldSnapshot.dayKey() else {
            logger.notice("snapshot missing or stale -> unplannedConfiguration")
            return unplannedConfiguration(penaltyAmount: penaltyAmount, appName: displayApp)
        }

        if !snapshot.shouldBlockApps {
            logger.notice("shouldBlockApps=false -> dayCompleteConfiguration")
            return dayCompleteConfiguration(appName: displayApp)
        }

        if !snapshot.hasPlannedDay {
            logger.notice("no planned day -> unplannedConfiguration")
            return unplannedConfiguration(penaltyAmount: penaltyAmount, appName: displayApp)
        }

        let now = Date()
        let timeFormatter = ISO8601DateFormatter()
        timeFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        logger.notice("time snapshot now=\(timeFormatter.string(from: now), privacy: .public) taskCount=\(snapshot.scheduledTasks.count)")
        for (index, task) in snapshot.scheduledTasks.enumerated() {
            let start = task.startTime.map { timeFormatter.string(from: $0) } ?? "nil"
            let end = task.endTime.map { timeFormatter.string(from: $0) } ?? "nil"
            logger.notice("task[\(index)] title=\(task.title, privacy: .public) start=\(start, privacy: .public) end=\(end, privacy: .public) isDone=\(task.isDone)")
        }

        let activeTasks = snapshot.activeTasks()
        if activeTasks.count > 1 {
            logger.notice("multiple active tasks -> multipleFocusConfiguration count=\(activeTasks.count, privacy: .public)")
            return multipleFocusConfiguration(penaltyAmount: penaltyAmount, tasks: activeTasks, now: now)
        } else if let active = activeTasks.first {
            logger.notice("active task found -> focusWindowConfiguration task=\(active.title, privacy: .public)")
            return focusWindowConfiguration(penaltyAmount: penaltyAmount, task: active, now: now)
        }

        logger.notice("planned day but no active task -> freeWindowConfiguration openCount=\(snapshot.openTaskTitles.count)")
        return freeWindowConfiguration(snapshot: snapshot, appName: displayApp)
    }

    private func baseShield(
        icon: UIImage?,
        title: String,
        subtitle: String,
        primaryLabel: String,
        incursPenalty: Bool,
        secondaryLabel: String = "Close"
    ) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThinMaterialLight,
            backgroundColor: ShieldTheme.background,
            icon: icon,
            title: ShieldConfiguration.Label(text: title, color: ShieldTheme.text),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: ShieldTheme.secondaryText),
            primaryButtonLabel: ShieldConfiguration.Label(text: primaryLabel, color: .white),
            primaryButtonBackgroundColor: incursPenalty ? ShieldTheme.destructive : ShieldTheme.primary,
            secondaryButtonLabel: ShieldConfiguration.Label(text: secondaryLabel, color: ShieldTheme.primary)
        )
    }

    /// Screen Time only supports a centered `icon` image; keep copy inside the artwork
    /// and hide system title/subtitle so the task text is not duplicated.
    private func baseShieldArtwork(
        icon: UIImage,
        primaryLabel: String,
        incursPenalty: Bool,
        secondaryLabel: String = "Close"
    ) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThinMaterialLight,
            backgroundColor: ShieldTheme.background,
            icon: icon,
            title: nil,
            subtitle: nil,
            primaryButtonLabel: ShieldConfiguration.Label(text: primaryLabel, color: .white),
            primaryButtonBackgroundColor: incursPenalty ? ShieldTheme.destructive : ShieldTheme.primary,
            secondaryButtonLabel: ShieldConfiguration.Label(text: secondaryLabel, color: ShieldTheme.primary)
        )
    }

    /// Shown only if a shield is briefly visible before the main app clears blocks.
    private func dayCompleteConfiguration(appName: String) -> ShieldConfiguration {
        baseShield(
            icon: UIImage(systemName: "checkmark.circle.fill"),
            title: "You're done for today",
            subtitle: "YourDay isn't blocking \(appName) anymore. Enjoy your break.",
            primaryLabel: "Close",
            incursPenalty: false
        )
    }

    private func unplannedConfiguration(penaltyAmount: Int, appName: String) -> ShieldConfiguration {
        let icon = ShieldArtwork.emptyTodayIllustration()
        return baseShield(
            icon: icon,
            title: "Plan your day first",
            subtitle: "Open YourDay and add at least one task to Today before opening \(appName).",
            primaryLabel: "Skip anyway (-\(penaltyAmount) pts)",
            incursPenalty: true
        )
    }

    private func focusWindowConfiguration(
        penaltyAmount: Int,
        task: ScheduledTaskBrief,
        now: Date
    ) -> ShieldConfiguration {
        let remaining = pomodoroClockString(end: task.endTime, now: now) ?? "--:--"
        logger.notice("focusWindowConfiguration task=\(task.title, privacy: .public) remaining=\(remaining, privacy: .public)")

        let icon = ShieldArtwork.pomodoroRingImage(
            start: task.startTime,
            end: task.endTime,
            now: now
        )
        return baseShield(
            icon: icon,
            title: task.title,
            subtitle: "⏱ \(remaining) left in this focus block",
            primaryLabel: "Break focus (-\(penaltyAmount) pts)",
            incursPenalty: true
        )
    }

    private func freeWindowConfiguration(snapshot: ShieldSnapshot, appName: String) -> ShieldConfiguration {
        let now = Date()
        let openTasks = sortedOpenTodayTasks(from: snapshot)
        let previewTasks = Array(openTasks.prefix(3))

        let icon = ShieldArtwork.taskListPreview(
            tasks: previewTasks,
            sectionTitle: "Today",
            sectionDotColor: ShieldTheme.mintAccent,
            trailingAccessory: .progress(done: snapshot.completedCount, total: snapshot.totalScheduledCount),
            showScheduleStatus: true,
            now: now
        )

        let subtitle: String
        if openTasks.isEmpty {
            subtitle = "All tasks for today are done. Nice work — \(appName) can wait."
        } else {
            let lines = openTasks.prefix(4).map { task in
                "• \(task.title) — \(ShieldArtwork.scheduleStatusLine(for: task, now: now))"
            }.joined(separator: "\n")
            var body = "You're between focus blocks. Finish what's on Today before opening \(appName).\n\n\(lines)"
            if openTasks.count > 4 {
                body += "\n\n+\(openTasks.count - 4) more not shown."
            }
            subtitle = body
        }

        return baseShield(
            icon: icon,
            title: "Before you scroll…",
            subtitle: subtitle,
            primaryLabel: "Continue anyway",
            incursPenalty: false
        )
    }

    private func sortedOpenTodayTasks(from snapshot: ShieldSnapshot) -> [ScheduledTaskBrief] {
        snapshot.openTodayTasks.sorted { lhs, rhs in
            switch (lhs.isCalendarScheduled, rhs.isCalendarScheduled) {
            case (true, false):
                return true
            case (false, true):
                return false
            case (true, true):
                let leftStart = lhs.startTime ?? .distantFuture
                let rightStart = rhs.startTime ?? .distantFuture
                if leftStart != rightStart { return leftStart < rightStart }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case (false, false):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func multipleFocusConfiguration(
        penaltyAmount: Int,
        tasks: [ScheduledTaskBrief],
        now: Date
    ) -> ShieldConfiguration {
        let icon = ShieldArtwork.multipleRingImage(tasks: Array(tasks.prefix(3)), now: now)

        let taskLines = tasks.prefix(4).map { task -> String in
            let remaining = pomodoroClockString(end: task.endTime, now: now) ?? "--:--"
            return "• \(task.title) (\(remaining) left)"
        }.joined(separator: "\n")

        return baseShield(
            icon: icon,
            title: "\(tasks.count) Overlapping Focus Blocks",
            subtitle: taskLines,
            primaryLabel: "Break focus (-\(penaltyAmount) pts)",
            incursPenalty: true
        )
    }

    private func pomodoroClockString(end: Date?, now: Date) -> String? {
        guard let end else { return nil }
        let interval = end.timeIntervalSince(now)
        guard interval > 0 else {
            logger.notice("pomodoroClockString interval non-positive")
            return nil
        }
        let totalSeconds = Int(interval.rounded(.down))
        let minutes = max(0, totalSeconds / 60)
        let seconds = max(0, totalSeconds % 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
