import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(appName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(appName: application.localizedDisplayName ?? category.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(appName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(appName: webDomain.domain ?? category.localizedDisplayName)
    }

    // MARK: - Shared builder

    private func makeConfiguration(appName: String?) -> ShieldConfiguration {
        let snapshot = AppGroupDefaults.loadSnapshot()
        let penaltyAmount = snapshot?.penaltyAmount ?? 100
        let displayApp = appName ?? "this app"

        let icon: UIImage? = UIImage(systemName: "leaf.circle.fill")
        let background = UIColor(red: 0.05, green: 0.1, blue: 0.08, alpha: 1.0)

        guard let snapshot, snapshot.dayKey == ShieldSnapshot.dayKey() else {
            return unplannedConfiguration(
                icon: icon,
                background: background,
                penaltyAmount: penaltyAmount,
                appName: displayApp
            )
        }

        if !snapshot.hasPlannedDay {
            return unplannedConfiguration(
                icon: icon,
                background: background,
                penaltyAmount: penaltyAmount,
                appName: displayApp
            )
        }

        if let active = snapshot.activeTask() {
            return focusWindowConfiguration(
                icon: icon,
                background: background,
                penaltyAmount: penaltyAmount,
                task: active
            )
        }

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
            backgroundBlurStyle: .systemThinMaterialDark,
            backgroundColor: background,
            icon: icon,
            title: ShieldConfiguration.Label(
                text: "Plan your day first",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Open YourDay and schedule at least one task before opening \(appName). Skipping now costs \(penaltyAmount) points.",
                color: UIColor(white: 0.9, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Skip anyway (-\(penaltyAmount) pts)",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.systemRed,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Back to YourDay",
                color: .white
            )
        )
    }

    private func focusWindowConfiguration(
        icon: UIImage?,
        background: UIColor,
        penaltyAmount: Int,
        task: ScheduledTaskBrief
    ) -> ShieldConfiguration {
        let remaining = remainingMinutes(until: task.endTime)
        let remainingText = remaining.map { "\($0) min left" } ?? "in progress"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemThinMaterialDark,
            backgroundColor: background,
            icon: icon,
            title: ShieldConfiguration.Label(
                text: "You're supposed to be focused",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Current task: \(task.title) (\(remainingText)). Breaking focus costs \(penaltyAmount) points.",
                color: UIColor(white: 0.9, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Break focus (-\(penaltyAmount) pts)",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.systemRed,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Back to YourDay",
                color: .white
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
            backgroundBlurStyle: .systemThinMaterialDark,
            backgroundColor: background,
            icon: icon,
            title: ShieldConfiguration.Label(
                text: "Before you scroll…",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor(white: 0.9, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Continue anyway",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor.systemGreen,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Back to YourDay",
                color: .white
            )
        )
    }

    private func remainingMinutes(until end: Date?) -> Int? {
        guard let end else { return nil }
        let interval = end.timeIntervalSinceNow
        guard interval > 0 else { return nil }
        return max(1, Int((interval / 60).rounded(.up)))
    }
}
