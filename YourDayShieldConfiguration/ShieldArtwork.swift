import UIKit

/// Draws task-list visuals for the Screen Time shield (matches `TodoListItemView` / `Todoview`).
enum ShieldArtwork {
    private static let canvasWidth: CGFloat = 300
    private static let compactRowHeight: CGFloat = 52
    private static let detailedRowHeight: CGFloat = 64
    private static let rowSpacing: CGFloat = 8

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Public

    /// Lower band where iOS draws real primary/secondary buttons on top of the background image.
    private static let buttonOverlayHeight: CGFloat = 200
    private static let horizontalPadding: CGFloat = 28
    private static let topPadding: CGFloat = 56

    private static var fullScreenCanvas: CGSize {
        let bounds = UIScreen.main.bounds.size
        return CGSize(width: max(bounds.width, 320), height: max(bounds.height, 480))
    }

    /// Full-screen bitmap for the free-window shield. System buttons are drawn above this (not inside it).
    static func freeWindowScreen(
        headline: String,
        message: String,
        tasks: [ScheduledTaskBrief],
        completedCount: Int,
        totalCount: Int,
        moreCount: Int,
        now: Date = Date()
    ) -> UIImage? {
        let size = fullScreenCanvas
        let width = size.width
        let contentWidth = width - horizontalPadding * 2
        let rowHeight = detailedRowHeight
        let sectionHeaderHeight: CGFloat = 36
        let contentBottomLimit = size.height - buttonOverlayHeight - 12

        let headlineFont = UIFont.systemFont(ofSize: 28, weight: .bold)
        let messageFont = UIFont.systemFont(ofSize: 16, weight: .regular)
        var displayTasks = Array(tasks.prefix(6))
        while displayTasks.count > 1,
              estimatedContentHeight(
                headline: headline,
                message: message,
                taskCount: displayTasks.count,
                moreCount: moreCount,
                contentWidth: contentWidth,
                headlineFont: headlineFont,
                messageFont: messageFont
              ) > contentBottomLimit - topPadding {
            displayTasks.removeLast()
        }

        let progressText = "\(completedCount) of \(totalCount) done today"

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            ShieldTheme.background.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            var y = topPadding

            y += drawMultilineText(
                headline,
                at: CGPoint(x: horizontalPadding, y: y),
                width: contentWidth,
                font: headlineFont,
                color: ShieldTheme.text
            ) + 12

            y += drawMultilineText(
                message,
                at: CGPoint(x: horizontalPadding, y: y),
                width: contentWidth,
                font: messageFont,
                color: ShieldTheme.secondaryText
            ) + 20

            if displayTasks.isEmpty {
                let placeholder = CGRect(x: horizontalPadding, y: y, width: contentWidth, height: 72)
                let path = UIBezierPath(roundedRect: placeholder, cornerRadius: 12)
                ShieldTheme.secondaryBackground.setFill()
                path.fill()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: ShieldTheme.secondaryText,
                ]
                let text = "No open tasks on Today"
                let textSize = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(
                    at: CGPoint(x: placeholder.midX - textSize.width / 2, y: placeholder.midY - textSize.height / 2),
                    withAttributes: attrs
                )
                y = placeholder.maxY + 14
            } else {
                drawSectionHeader(
                    in: cg,
                    rect: CGRect(x: horizontalPadding, y: y, width: contentWidth, height: sectionHeaderHeight),
                    title: "Today",
                    dotColor: ShieldTheme.mintAccent
                )
                y += sectionHeaderHeight + 4

                for (index, task) in displayTasks.enumerated() {
                    let stripColor = index.isMultiple(of: 2) ? ShieldTheme.peachAccent : ShieldTheme.mintAccent
                    drawTaskRow(
                        in: cg,
                        rect: CGRect(x: horizontalPadding, y: y, width: contentWidth, height: rowHeight),
                        title: task.title,
                        isDone: task.isDone,
                        stripColor: stripColor,
                        scheduleCaption: scheduleStatusLine(for: task, now: now),
                        timerText: nil
                    )
                    y += rowHeight + rowSpacing
                }
                y += 6
            }

            y += drawMultilineText(
                progressText,
                at: CGPoint(x: horizontalPadding, y: y),
                width: contentWidth,
                font: UIFont.systemFont(ofSize: 14, weight: .medium),
                color: ShieldTheme.secondaryText
            ) + 8

            let hiddenCount = moreCount + max(0, tasks.count - displayTasks.count)
            if hiddenCount > 0 {
                _ = drawMultilineText(
                    "+\(hiddenCount) more not shown",
                    at: CGPoint(x: horizontalPadding, y: y),
                    width: contentWidth,
                    font: UIFont.systemFont(ofSize: 14, weight: .medium),
                    color: ShieldTheme.secondaryText
                )
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func estimatedContentHeight(
        headline: String,
        message: String,
        taskCount: Int,
        moreCount: Int,
        contentWidth: CGFloat,
        headlineFont: UIFont,
        messageFont: UIFont
    ) -> CGFloat {
        let headlineHeight = measuredTextHeight(headline, width: contentWidth, font: headlineFont)
        let messageHeight = measuredTextHeight(message, width: contentWidth, font: messageFont)
        let progressHeight: CGFloat = 22
        let moreHeight: CGFloat = moreCount > 0 ? 22 : 0
        let tasksBlockHeight: CGFloat
        if taskCount == 0 {
            tasksBlockHeight = 88
        } else {
            tasksBlockHeight = 36 + 4 + CGFloat(taskCount) * (detailedRowHeight + rowSpacing)
        }
        return headlineHeight + 12 + messageHeight + 20 + tasksBlockHeight + 14 + progressHeight + moreHeight + 8
    }

    static func scheduleStatusLine(for task: ScheduledTaskBrief, now: Date = Date()) -> String {
        guard task.isCalendarScheduled else { return "Not scheduled" }
        guard let start = task.startTime else { return "Scheduled" }
        let time = timeFormatter.string(from: start)
        if start > now {
            return "Scheduled · starts \(time)"
        }
        return "Scheduled · \(time)"
    }

    static func taskListPreview(
        tasks: [ScheduledTaskBrief],
        sectionTitle: String,
        sectionDotColor: UIColor,
        trailingAccessory: TrailingAccessory? = nil,
        showScheduleStatus: Bool = false,
        now: Date = Date()
    ) -> UIImage? {
        let rows = Array(tasks.prefix(3))
        guard !rows.isEmpty else { return emptyTodayIllustration() }

        let rowHeight = showScheduleStatus ? detailedRowHeight : compactRowHeight
        let headerHeight: CGFloat = 36
        let accessoryHeight: CGFloat = trailingAccessory == nil ? 0 : 44
        let height = headerHeight + CGFloat(rows.count) * (rowHeight + rowSpacing) + accessoryHeight + 12
        let size = CGSize(width: canvasWidth, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            var y: CGFloat = 0

            drawSectionHeader(
                in: cg,
                rect: CGRect(x: 0, y: y, width: canvasWidth, height: headerHeight),
                title: sectionTitle,
                dotColor: sectionDotColor
            )
            y += headerHeight + 4

            for (index, task) in rows.enumerated() {
                let stripColor = index.isMultiple(of: 2) ? ShieldTheme.peachAccent : ShieldTheme.mintAccent
                drawTaskRow(
                    in: cg,
                    rect: CGRect(x: 0, y: y, width: canvasWidth, height: rowHeight),
                    title: task.title,
                    isDone: task.isDone,
                    stripColor: stripColor,
                    scheduleCaption: showScheduleStatus ? scheduleStatusLine(for: task, now: now) : nil,
                    timerText: showScheduleStatus ? nil : timerLabel(for: task, now: now)
                )
                y += rowHeight + rowSpacing
            }

            if let trailingAccessory {
                drawAccessory(
                    in: cg,
                    rect: CGRect(x: 0, y: y, width: canvasWidth, height: accessoryHeight),
                    accessory: trailingAccessory
                )
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    static func pomodoroRingImage(
        start: Date?,
        end: Date?,
        now: Date,
        size: CGFloat = 160,
        lineWidth: CGFloat = 14
    ) -> UIImage? {
        let canvas = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { ctx in
            drawPomodoroRing(
                in: ctx.cgContext,
                rect: CGRect(origin: .zero, size: canvas),
                start: start,
                end: end,
                now: now,
                lineWidth: lineWidth
            )
        }.withRenderingMode(.alwaysOriginal)
    }

    static func multipleRingImage(tasks: [ScheduledTaskBrief], now: Date, size: CGFloat = 160) -> UIImage? {
        guard !tasks.isEmpty else { return nil }
        let lineWidth: CGFloat = 11
        let ringSpacing: CGFloat = 4
        let canvas = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)

        let progressColors: [UIColor] = [
            ShieldTheme.primary,
            UIColor(hex: "#3A9C75"),
            ShieldTheme.secondary,
        ]

        return renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)

            for (index, task) in tasks.enumerated() {
                let radius = (size - lineWidth) / 2 - CGFloat(index) * (lineWidth + ringSpacing)
                guard radius > lineWidth / 2 else { continue }

                let remainingFraction: CGFloat
                if let start = task.startTime, let end = task.endTime, end > start {
                    let total = end.timeIntervalSince(start)
                    let elapsed = max(0, min(total, now.timeIntervalSince(start)))
                    remainingFraction = CGFloat(max(0, min(1, 1 - elapsed / total)))
                } else {
                    remainingFraction = 0
                }

                let progressColor = index < progressColors.count ? progressColors[index] : progressColors.last!

                cg.setLineWidth(lineWidth)
                cg.setStrokeColor(ShieldTheme.trackMint.cgColor)
                cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                cg.strokePath()

                guard remainingFraction > 0 else { continue }
                cg.setLineCap(.round)
                cg.setStrokeColor(progressColor.cgColor)
                let startAngle: CGFloat = -.pi / 2
                let endAngle = startAngle + .pi * 2 * remainingFraction
                cg.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                cg.strokePath()
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    static func emptyTodayIllustration() -> UIImage? {
        let size = CGSize(width: canvasWidth, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            drawSectionHeader(
                in: cg,
                rect: CGRect(x: 0, y: 0, width: canvasWidth, height: 36),
                title: "Today",
                dotColor: ShieldTheme.mintAccent
            )
            let placeholder = CGRect(x: 0, y: 44, width: canvasWidth, height: compactRowHeight)
            let path = UIBezierPath(roundedRect: placeholder, cornerRadius: 10)
            ShieldTheme.secondaryBackground.setFill()
            path.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: ShieldTheme.secondaryText,
            ]
            let text = "Add tasks in YourDay"
            let textSize = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: CGPoint(x: placeholder.midX - textSize.width / 2, y: placeholder.midY - textSize.height / 2),
                withAttributes: attrs
            )
        }.withRenderingMode(.alwaysOriginal)
    }

    // MARK: - Drawing primitives

    private static func drawSectionHeader(
        in cg: CGContext,
        rect: CGRect,
        title: String,
        dotColor: UIColor
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        cg.saveGState()
        cg.addPath(path.cgPath)
        cg.clip()
        let colors = [ShieldTheme.mintAccent.withAlphaComponent(0.35).cgColor, ShieldTheme.secondaryBackground.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.midY),
                end: CGPoint(x: rect.maxX, y: rect.midY),
                options: []
            )
        }
        cg.restoreGState()

        let dotRect = CGRect(x: rect.minX + 12, y: rect.midY - 5, width: 10, height: 10)
        cg.setFillColor(dotColor.cgColor)
        cg.fillEllipse(in: dotRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: ShieldTheme.text,
        ]
        (title as NSString).draw(at: CGPoint(x: dotRect.maxX + 8, y: rect.midY - 9), withAttributes: attrs)
    }

    private static func drawTaskRow(
        in cg: CGContext,
        rect: CGRect,
        title: String,
        isDone: Bool,
        stripColor: UIColor,
        scheduleCaption: String?,
        timerText: String?
    ) {
        let cardPath = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        ShieldTheme.secondaryBackground.setFill()
        cardPath.fill()

        let stripRect = CGRect(x: rect.minX + 6, y: rect.minY + 8, width: 4, height: rect.height - 16)
        let stripPath = UIBezierPath(roundedRect: stripRect, cornerRadius: 2)
        stripColor.setFill()
        stripPath.fill()

        let contentMidY = scheduleCaption == nil ? rect.midY : rect.minY + 22
        let checkboxCenter = CGPoint(x: rect.minX + 28, y: contentMidY)
        let checkboxRadius: CGFloat = 13
        cg.setStrokeColor((isDone ? ShieldTheme.primary : ShieldTheme.secondaryText).cgColor)
        cg.setLineWidth(1.5)
        cg.strokeEllipse(in: CGRect(
            x: checkboxCenter.x - checkboxRadius,
            y: checkboxCenter.y - checkboxRadius,
            width: checkboxRadius * 2,
            height: checkboxRadius * 2
        ))
        if isDone {
            cg.setFillColor(ShieldTheme.primary.withAlphaComponent(0.2).cgColor)
            cg.fillEllipse(in: CGRect(
                x: checkboxCenter.x - checkboxRadius,
                y: checkboxCenter.y - checkboxRadius,
                width: checkboxRadius * 2,
                height: checkboxRadius * 2
            ))
            let check = "✓" as NSString
            let checkAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: ShieldTheme.primary,
            ]
            let checkSize = check.size(withAttributes: checkAttrs)
            check.draw(
                at: CGPoint(x: checkboxCenter.x - checkSize.width / 2, y: checkboxCenter.y - checkSize.height / 2 - 1),
                withAttributes: checkAttrs
            )
        }

        let titleX = rect.minX + 50
        let reservedRight: CGFloat = timerText == nil ? 12 : 64
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: isDone ? ShieldTheme.secondaryText : ShieldTheme.text,
            .strikethroughStyle: isDone ? NSUnderlineStyle.single.rawValue : 0,
        ]
        let truncated = truncatedTitle(title, maxWidth: rect.width - 56 - reservedRight)
        let titleY = scheduleCaption == nil ? contentMidY - 9 : rect.minY + 10
        (truncated as NSString).draw(at: CGPoint(x: titleX, y: titleY), withAttributes: titleAttrs)

        if let scheduleCaption {
            let captionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: scheduleCaption.hasPrefix("Not scheduled")
                    ? ShieldTheme.secondaryText
                    : ShieldTheme.primary,
            ]
            (scheduleCaption as NSString).draw(
                at: CGPoint(x: titleX, y: titleY + 18),
                withAttributes: captionAttrs
            )
        }

        if let timerText {
            let timerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: ShieldTheme.primary,
            ]
            let timerSize = (timerText as NSString).size(withAttributes: timerAttrs)
            (timerText as NSString).draw(
                at: CGPoint(x: rect.maxX - timerSize.width - 12, y: contentMidY - timerSize.height / 2),
                withAttributes: timerAttrs
            )
        }
    }

    private static func drawPomodoroRing(
        in cg: CGContext,
        rect: CGRect,
        start: Date?,
        end: Date?,
        now: Date,
        lineWidth: CGFloat = 8
    ) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - lineWidth / 2 - 2

        cg.setLineWidth(lineWidth)
        cg.setStrokeColor(ShieldTheme.trackMint.cgColor)
        cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        cg.strokePath()

        guard let start, let end, end > start else { return }
        let total = end.timeIntervalSince(start)
        let elapsed = max(0, min(total, now.timeIntervalSince(start)))
        let remainingFraction = CGFloat(max(0, min(1, 1 - elapsed / total)))
        guard remainingFraction > 0 else { return }

        cg.setLineCap(.round)
        cg.setStrokeColor(ShieldTheme.primary.cgColor)
        let startAngle: CGFloat = -.pi / 2
        let endAngle = startAngle + .pi * 2 * remainingFraction
        cg.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        cg.strokePath()
    }

    private static func drawAccessory(
        in cg: CGContext,
        rect: CGRect,
        accessory: TrailingAccessory
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: ShieldTheme.secondaryText,
        ]
        (accessory.label as NSString).draw(
            at: CGPoint(x: rect.minX + 8, y: rect.midY - 8),
            withAttributes: attrs
        )
    }

    // MARK: - Helpers

    enum TrailingAccessory {
        case progress(done: Int, total: Int)

        var label: String {
            switch self {
            case let .progress(done, total):
                return "\(done) of \(total) done today"
            }
        }
    }

    private static func timerLabel(for task: ScheduledTaskBrief, now: Date = Date()) -> String? {
        guard let end = task.endTime else { return nil }
        let interval = end.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        let totalSeconds = Int(interval.rounded(.down))
        let minutes = max(0, totalSeconds / 60)
        let seconds = max(0, totalSeconds % 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @discardableResult
    private static func drawMultilineText(
        _ text: String,
        at origin: CGPoint,
        width: CGFloat,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let height = measuredTextHeight(text, width: width, font: font, alignment: alignment)
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return height
    }

    private static func measuredTextHeight(
        _ text: String,
        width: CGFloat,
        font: UIFont,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return ceil(rect.height)
    }

    private static func truncatedTitle(_ title: String, maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .regular)]
        if (title as NSString).size(withAttributes: attrs).width <= maxWidth { return title }
        var trimmed = title
        while trimmed.count > 1 {
            trimmed = String(trimmed.dropLast())
            let candidate = trimmed + "…"
            if (candidate as NSString).size(withAttributes: attrs).width <= maxWidth { return candidate }
        }
        return "…"
    }
}
