import XCTest

final class PreviewUITests: XCTestCase {
    @MainActor func testPreviewMakesItsLimitsExplicitAndOpensMessage() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Offline preview · fictional messages · no live encryption"].waitForExistence(timeout: 10))
        app.buttons["Explore the interaction preview"].tap()
        XCTAssertTrue(app.staticTexts["INTERACTION PREVIEW"].waitForExistence(timeout: 5))
        app.staticTexts["Jamie"].tap()
        let open = app.buttons["New message. Open for up to 60 seconds."].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.staticTexts["Meet by the little bookshop at six?"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Conversation interaction preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
