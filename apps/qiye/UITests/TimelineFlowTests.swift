import XCTest

@MainActor
final class TimelineFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "top.mmddskq.qiye")
        app.launchArguments = ["--tab", "talks", "--uitest-content", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
    }
    override func tearDownWithError() throws {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Timeline final"; image.lifetime = .keepAlways; add(image)
        if testRun?.hasSucceeded == false { let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy) }
        app.terminate(); app = nil
    }
    func testSixGridAndNativeViewerDismiss() {
        let row = app.descendants(matching: .any)["talk-row-fixture-six"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let buttons = row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "talk-image-"))
        XCTAssertEqual(buttons.count, 6)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Six images in three columns"; screenshot.lifetime = .keepAlways; add(screenshot)
        buttons.element(boundBy: 0).tap()
        let viewer = app.descendants(matching: .any)["media-viewer"].firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: 5), "An image must open inside the app")
        XCTAssertEqual(app.state, .runningForeground)
        viewer.swipeDown()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: viewer)], timeout: 5) == .completed)
        XCTAssertTrue(app.segmentedControls["talk-status-picker"].waitForExistence(timeout: 5))
    }
    func testUnpublishDeleteAndRestore() {
        let menu = app.buttons["talk-actions-fixture-six"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        app.buttons["下架到未发表"].tap()
        let states = app.segmentedControls["talk-status-picker"]
        states.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "未发表")).firstMatch.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap()
        app.buttons["移到已删除"].tap()
        app.sheets.buttons["移到已删除"].tap()
        states.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "已删除")).firstMatch.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap()
        app.buttons["恢复到未发表"].tap()
        states.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "未发表")).firstMatch.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
    }
    func testNineGridHasThreeRows() {
        app.terminate()
        app.launchArguments += ["--nine-first"]
        app.launch()
        let row = app.descendants(matching: .any)["talk-row-fixture-nine"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let images = row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "talk-image-"))
        XCTAssertEqual(images.count, 9)
        XCTAssertEqual(images.element(boundBy: 0).frame.minY, images.element(boundBy: 2).frame.minY, accuracy: 2)
        XCTAssertGreaterThan(images.element(boundBy: 3).frame.minY, images.element(boundBy: 0).frame.minY)
        XCTAssertGreaterThan(images.element(boundBy: 6).frame.minY, images.element(boundBy: 3).frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Nine images in three rows"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
