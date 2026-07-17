//
//  GardenSceneSmokeTests.swift
//  YourDayUITests
//
//  Smoke test for the SpriteKit garden scene: boots as a local guest via the
//  -UITestGardenSmoke seam, opens the Garden tab, exercises pinch zoom and
//  pan, and captures screenshots at each state for visual review.
//
//  Run:
//    xcodebuild -project YourDay.xcodeproj -scheme YourDay \
//      -destination 'platform=iOS Simulator,name=iPhone 16' \
//      -only-testing:YourDayUITests/GardenSceneSmokeTests test
//
//  Screenshots land in the .xcresult bundle; export with:
//    xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>
//

import XCTest

final class GardenSceneSmokeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterLaunchFailures()
    }

    private func continueAfterLaunchFailures() {
        continueAfterFailure = false
    }

    @MainActor
    func testGardenSceneRendersZoomsAndPans() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestGardenSmoke",
            // @AppStorage reads the argument domain — suppresses the garden
            // tutorial overlay so screenshots show the scene itself.
            "-hasCompletedGardenTutorial_v1", "YES",
        ]

        // Location is pre-granted via simctl in CI; anything else (e.g.
        // notifications) gets dismissed here.
        addUIInterruptionMonitor(withDescription: "System permission alerts") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow", "OK", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()

        let gardenTab = app.tabBars.buttons["Garden"]
        XCTAssertTrue(
            gardenTab.waitForExistence(timeout: 20),
            "Garden tab never appeared — guest seam may not have run"
        )
        gardenTab.tap() // idempotent (seam preselects it); also flushes any alert

        // Let the scene build, camera settle, and clouds fade in.
        sleep(4)
        attachScreenshot(named: "1-garden-min-zoom")

        // Zoom in toward max (maxZoom/minZoom ≈ 3.7×).
        let window = app.windows.firstMatch
        window.pinch(withScale: 2.5, velocity: 1.5)
        window.pinch(withScale: 2.0, velocity: 1.5)
        sleep(1)
        attachScreenshot(named: "2-garden-max-zoom")

        // Pan across the island at high zoom.
        window.swipeLeft()
        sleep(1)
        attachScreenshot(named: "3-garden-panned")

        // Zoom back out to the clamped minimum.
        window.pinch(withScale: 0.15, velocity: -1.5)
        sleep(1)
        attachScreenshot(named: "4-garden-zoomed-out")

        // The world should still be interactive: tapping the island area of an
        // empty plot at min zoom opens the planting inventory sheet only when
        // zoomed enough to hit a tile — at min zoom just assert no crash and
        // the tab bar is still present.
        XCTAssertTrue(gardenTab.exists, "App remained alive after gestures")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
