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

        let icon: UIImage? = UIImage(systemName: "checklist.checked")
        let background = UIColor(red: 0.95, green: 0.98, blue: 0.96, alpha: 1.0)

        guard let snapshot, snapshot.dayKey == ShieldSnapshot.dayKey() else {
            logger.notice("snapshot missing or stale -> unplannedConfiguration")
            return unplannedConfiguration(
                icon: icon,
                background: background,
                penaltyAmount: penaltyAmount,
                appName: displayApp
            )
        }

        if !snapshot.hasPlannedDay {
            logger.notice("no planned day -> unplannedConfiguration")
            return unplannedConfiguration(
                icon: icon,
                background: background,
                penaltyAmount: penaltyAmount,
                appName: displayApp
            )
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

        if let active = snapshot.activeTask() {
            logger.notice("active task found -> focusWindowConfiguration task=\(active.title, privacy: .public)")
            return focusWindowConfiguration(
                icon: icon,
                background: background,
                penaltyAmount: penaltyAmount,
                task: active
            )
        }

        logger.notice("planned day but no active task -> freeWindowConfiguration openCount=\(snapshot.openTaskTitles.count)")
        return freeWindowConfiguration(
            icon: icon,
            background: background,
            snapshot: snapshot,
            appName: displayApp
        )
    }

    private func unplannedConfiguration(
        icon: UIImage?,
        background: UIColor,
        penaltyAmount: Int,
        appName: String
    ) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThinMaterialLight,
            backgroundColor: background,
            icon: icon,
            title: ShieldConfiguration.Label(
                text: "Plan your day first",
                color: UIColor(red: 0.1, green: 0.26, blue: 0.2, alpha: 1.0)
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Open YourDay and schedule at least one task before opening \(appName).",
                color: UIColor(red: 0.22, green: 0.34, blue: 0.28, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Skip anyway (-\(penaltyAmount) pts)",
                color: .white
            ),
            primaryButtonBackgroundColor: primaryButtonColor(incursPenalty: true),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Close",
                color: UIColor(red: 0.17, green: 0.53, blue: 0.38, alpha: 1.0)
            )
        )
    }

    private func focusWindowConfiguration(
        icon: UIImage?,
        background: UIColor,
        penaltyAmount: Int,
        task: ScheduledTaskBrief
    ) -> ShieldConfiguration {
        let now = Date()
        let pomodoroRemaining = pomodoroClockString(end: task.endTime, now: now) ?? "--:--"
        logger.notice("focusWindowConfiguration task=\(task.title, privacy: .public) remaining=\(pomodoroRemaining, privacy: .public)")

        let ringIcon = pomodoroRingImage(
            start: task.startTime,
            end: task.endTime,
            now: now
        ) ?? UIImage(systemName: "timer") ?? icon

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThinMaterialLight,
            backgroundColor: background,
            icon: ringIcon,
            title: ShieldConfiguration.Label(
                text: "\(task.title)",
                color: UIColor(red: 0.1, green: 0.26, blue: 0.2, alpha: 1.0)
            ),
            subtitle: ShieldConfiguration.Label(
                text: "⏱ \(pomodoroRemaining) left in this focus block",
                color: UIColor(red: 0.22, green: 0.34, blue: 0.28, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Break focus (-\(penaltyAmount) pts)",
                color: .white
            ),
            primaryButtonBackgroundColor: primaryButtonColor(incursPenalty: true),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Close",
                color: UIColor(red: 0.17, green: 0.53, blue: 0.38, alpha: 1.0)
            )
        )
    }

    private func freeWindowConfiguration(
        icon: UIImage?,
        background: UIColor,
        snapshot: ShieldSnapshot,
        appName: String
    ) -> ShieldConfiguration {
        let openTitles = Array(snapshot.openTaskTitles.prefix(5))
        let bullets = openTitles.map { "• \($0)" }.joined(separator: "\n")
        let doneLine = "\(snapshot.completedCount) of \(snapshot.totalScheduledCount) done today"
        let subtitle: String
        if bullets.isEmpty {
            subtitle = "All scheduled tasks are done. \(doneLine)."
        } else {
            subtitle = "\(bullets)\n\n\(doneLine)."
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThinMaterialLight,
            backgroundColor: background,
            icon: icon,
            title: ShieldConfiguration.Label(
                text: "Before you scroll…",
                color: UIColor(red: 0.1, green: 0.26, blue: 0.2, alpha: 1.0)
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor(red: 0.22, green: 0.34, blue: 0.28, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Continue anyway",
                color: .white
            ),
            primaryButtonBackgroundColor: primaryButtonColor(incursPenalty: false),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Close",
                color: UIColor(red: 0.17, green: 0.53, blue: 0.38, alpha: 1.0)
            )
        )
    }

    private func primaryButtonColor(incursPenalty: Bool) -> UIColor {
        if incursPenalty {
            return UIColor(red: 0.87, green: 0.24, blue: 0.26, alpha: 1.0)
        }
        return UIColor(red: 0.22, green: 0.69, blue: 0.47, alpha: 1.0)
    }

    private func pomodoroRingImage(
        start: Date?,
        end: Date?,
        now: Date,
        size: CGFloat = 160,
        lineWidth: CGFloat = 14
    ) -> UIImage? {
        guard let start, let end, end > start else { return nil }
        let total = end.timeIntervalSince(start)
        let elapsed = max(0, min(total, now.timeIntervalSince(start)))
        let remainingFraction = CGFloat(max(0, min(1, 1 - elapsed / total)))

        let canvas = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = (size - lineWidth) / 2

            let trackColor = UIColor(red: 0.80, green: 0.92, blue: 0.86, alpha: 1.0)
            let progressColor = UIColor(red: 0.17, green: 0.53, blue: 0.38, alpha: 1.0)

            cg.setLineWidth(lineWidth)
            cg.setStrokeColor(trackColor.cgColor)
            cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cg.strokePath()

            cg.setLineCap(.round)
            cg.setStrokeColor(progressColor.cgColor)
            let startAngle: CGFloat = -.pi / 2
            let endAngle = startAngle + .pi * 2 * remainingFraction
            cg.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            cg.strokePath()
        }
        return image.withRenderingMode(.alwaysOriginal)
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
