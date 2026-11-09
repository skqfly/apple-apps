import XCTest

/// Runs against the real app with a deterministic, local-only portrait fixture.
/// See UITests/README.md for the launch argument and accessibility contract.
@MainActor
final class LongPhotoHitAreaTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication(bundleIdentifier: "top.mmddskq.qiye")
        app.launchArguments = [
            "--tab", "photos", "--uitest-long-photo",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        if let app {
            attachScreenshot("Final state")
            if testRun?.hasSucceeded == false {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Accessibility hierarchy on failure"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            app.terminate()
        }
        app = nil
    }

    func testLongPortraitDraftDoesNotInterceptWebsiteSegmentTap() throws {
        let sourcePicker = app.descendants(matching: .any)["content-status-picker"].firstMatch
        XCTAssertTrue(sourcePicker.waitForExistence(timeout: 10), "Photos source picker must be exposed.")

        let draftsSegment = app.buttons["content-status-unpublished"]
        let websiteSegment = app.buttons["content-status-published"]
        XCTAssertTrue(draftsSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(websiteSegment.exists)
        if !draftsSegment.isSelected { draftsSegment.tap() }
        XCTAssertTrue(waitForSelection(draftsSegment), "The fixture's draft source must be selected.")

        let draft = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR identifier BEGINSWITH %@",
            "photo-draft", "photo-draft-"
        )).firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5), "--uitest-long-photo must inject a visible long portrait draft.")
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR identifier BEGINSWITH %@",
            "photo-draft", "photo-draft-"
        )).count, 1, "The fixture must contain exactly one draft, independent of stored user data.")

        XCTAssertTrue(waitForAbsence(draft.activityIndicators.firstMatch), "The long thumbnail must finish loading before testing its hit area.")
        XCTAssertFalse(app.staticTexts["无法读取本地照片"].exists, "A missing image would make the hit-area check meaningless.")

        // Positive control: prove that the same card really opens photo details,
        // and that the detail identifier can detect the accidental presentation.
        XCTAssertTrue(draft.isHittable)
        draft.tap()
        let detail = app.descendants(matching: .any).matching(identifier: "photo-detail-screen").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "A card tap must open the real photo detail screen.")
        attachScreenshot("Long portrait detail — positive control")
        let closeButton = app.buttons["关闭"].firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()
        XCTAssertTrue(waitForAbsence(detail), "Close must return to the draft grid.")
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertTrue(draftsSegment.isSelected)
        attachScreenshot("Before website tap — long portrait draft")

        // Use the segment's physical center, as a finger would. A normal .tap()
        // can choose an alternate hittable point and conceal an overlapping image.
        XCTAssertTrue(websiteSegment.isHittable)
        websiteSegment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForSelection(websiteSegment), "Tapping 网站 must select the website source; a long image must not steal the touch.")
        XCTAssertFalse(draftsSegment.isSelected)
        XCTAssertFalse(detail.exists, "Tapping 网站 must never present photo details.")
        XCTAssertTrue(waitForAbsence(draft), "The local draft grid must disappear when 网站 is selected.")
        XCTAssertTrue(sourcePicker.isHittable, "Source controls must remain usable after the switch.")
        attachScreenshot("After website tap — website selected")

        // Switching back also proves the fixture was not deleted or lost.
        draftsSegment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertFalse(detail.exists)
    }

    private func waitForSelection(_ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true OR selected == true"), object: element
        )], timeout: 5) == .completed
    }

    private func waitForAbsence(_ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element
        )], timeout: 5) == .completed
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
