import XCTest

/// Drives the app with real touches for the README screenshots. `scripts/capture-screenshots.sh`
/// takes each picture with `simctl io` from outside the test: the test parks on a marker file until
/// the host has captured the frame. It skips itself in ordinary test runs.
@MainActor
final class ScreenshotTour: XCTestCase {
    private var directory: String?

    override func setUp() async throws {
        directory = ProcessInfo.processInfo.environment["DOODLEDEX_SHOT_DIR"]
        try XCTSkipIf(directory == nil, "only runs under scripts/capture-screenshots.sh")
        continueAfterFailure = false
    }

    private func capture(_ name: String) throws {
        let folder = URL(filePath: try XCTUnwrap(directory))
        try Data().write(to: folder.appending(path: "\(name).ready"))
        let done = folder.appending(path: "\(name).done").path(percentEncoded: false)
        let deadline = Date.now.addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: done), Date.now < deadline {
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.1))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: done), "host did not capture \(name)")
    }

    func testTour() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--fresh-collection"]
        app.launch()
        let robot = SketchRobot(app: app)
        XCTAssertTrue(robot.canvas.waitForExistence(timeout: 20))
        try capture("01-empty")

        let house = Shapes.house
        robot.draw(Array(house.prefix(3)))
        XCTAssertTrue(robot.waitForFootnote(strokes: 3))
        try capture("02-partial")
        robot.draw(Array(house.dropFirst(3)))
        XCTAssertTrue(robot.waitForFootnote(strokes: house.count))
        try capture("03-sure")
        app.buttons["sketch.collect"].tap()
        try capture("04-sticker")

        for shape in [Shapes.star, Shapes.ladder, Shapes.envelope, Shapes.tent, Shapes.fish] {
            let wait = app.buttons["sketch.collect"]
            robot.draw(shape)
            XCTAssertTrue(robot.waitForFootnote(strokes: shape.count))
            if wait.isEnabled {
                wait.tap()
            } else {
                app.buttons["sketch.clear"].tap()
            }
            sleep(2)
        }

        app.tabBars.buttons["Dex"].tap()
        try capture("05-dex")
        app.buttons["dex.about"].tap()
        XCTAssertTrue(app.staticTexts["about.attribution"].waitForExistence(timeout: 5))
        try capture("06-about")
    }
}
