import XCTest

/// The whole loop with real touches: draw, get recognized, collect, kill the app, find the sticker
/// still in the book. The relaunch is what proves SwiftData wrote to disk.
@MainActor
final class DrawingFlowTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = fresh ? ["--fresh-collection"] : []
        app.launch()
        return app
    }

    func testDrawnHouseIsRecognizedCollectedAndSurvivesRelaunch() throws {
        let app = launch(fresh: true)
        let robot = SketchRobot(app: app)
        XCTAssertTrue(robot.canvas.waitForExistence(timeout: 20))

        robot.draw(Shapes.house)
        XCTAssertTrue(robot.waitForFootnote(strokes: Shapes.house.count))

        let collect = app.buttons["sketch.collect"]
        XCTAssertTrue(collect.isEnabled, "the model should be sure of a house with a door")
        XCTAssertEqual(collect.label, "Stick House in the Dex")
        collect.tap()

        app.tabBars.buttons["Dex"].tap()
        XCTAssertEqual(app.staticTexts["dex.count"].label, "1 of 100 stickers")
        XCTAssertTrue(app.buttons["dex.latest.house"].waitForExistence(timeout: 5))

        app.terminate()
        let relaunched = launch(fresh: false)
        relaunched.tabBars.buttons["Dex"].tap()
        XCTAssertEqual(relaunched.staticTexts["dex.count"].label, "1 of 100 stickers")
        XCTAssertTrue(relaunched.buttons["dex.latest.house"].waitForExistence(timeout: 5))
    }

    func testUndoRemovesAStrokeAndRewindsTheStrokeCount() throws {
        let app = launch(fresh: true)
        let robot = SketchRobot(app: app)
        XCTAssertTrue(robot.canvas.waitForExistence(timeout: 20))

        robot.draw(Array(Shapes.star.prefix(3)))
        XCTAssertTrue(robot.waitForFootnote(strokes: 3))

        app.buttons["sketch.undo"].tap()
        XCTAssertTrue(robot.waitForFootnote(strokes: 2))
    }
}
