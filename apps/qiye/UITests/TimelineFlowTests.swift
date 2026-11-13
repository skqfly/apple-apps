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
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Timeline final"
        image.lifetime = .keepAlways
        add(image)
        if testRun?.hasSucceeded == false {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
        app = nil
    }

    func testSixGridAndNativeViewerDismiss() {
        let row = app.descendants(matching: .any)["talk-row-fixture-six"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let buttons = row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "talk-image-"))
        XCTAssertEqual(buttons.count, 6)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Six images in three columns"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        buttons.element(boundBy: 0).tap()
        let viewer = app.descendants(matching: .any)["media-viewer"].firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: 5), "An image must open inside the app")
        XCTAssertEqual(app.state, .runningForeground)
        viewer.swipeDown()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: viewer)], timeout: 5) == .completed)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testUnpublishDeleteAndRestore() {
        let menu = app.buttons["talk-actions-fixture-six"]
        let badge = app.descendants(matching: .any)["talk-status-badge-fixture-six"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue(badge.label.contains("已发表"))

        menu.tap()
        app.buttons["下架到未发表"].tap()
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue(badge.label.contains("未发表"))

        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["移到已删除"].tap()
        app.sheets.buttons["移到已删除"].tap()
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue(badge.label.contains("已删除"))

        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["恢复到未发表"].tap()
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue(badge.label.contains("未发表"))
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
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Nine images in three rows"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCollectionNavigationWalkthrough() {
        app.terminate()
        app.launchArguments = ["--tab", "home", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["collection-photos"].waitForExistence(timeout: 15))
        capture("Collections home")

        app.tabBars.buttons["文章"].tap()
        let article = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "article-")).firstMatch
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        capture("Article collection")
        article.tap()
        XCTAssertTrue(app.navigationBars["文章"].waitForExistence(timeout: 5))
        capture("Article reader")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["图片"].tap()
        let photo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "photo-tile-")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        capture("Photo collection")
        photo.tap()
        let close = app.buttons["关闭"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let thumbnails = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "转到第"))
        XCTAssertGreaterThan(thumbnails.count, 1, "The first photo must open with the complete collection for browsing")
        thumbnails.element(boundBy: 1).tap()
        capture("Photo filmstrip")
        close.tap()

        app.tabBars.buttons["收藏"].tap()
        let projects = app.buttons["collection-projects"]
        if !projects.isHittable { app.swipeUp() }
        XCTAssertTrue(projects.waitForExistence(timeout: 5))
        projects.tap()
        XCTAssertTrue(app.descendants(matching: .any)["directory-projects"].firstMatch.waitForExistence(timeout: 5))
        capture("Projects")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let friends = app.buttons["collection-friends"]
        if !friends.isHittable { app.swipeUp() }
        friends.tap()
        XCTAssertTrue(app.descendants(matching: .any)["directory-friends"].firstMatch.waitForExistence(timeout: 5))
        capture("Friends")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
