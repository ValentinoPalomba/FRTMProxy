import XCTest

final class ScreenshotUITests: XCTestCase {

    private let proxyPort = "8080"

    private var outputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["FRTM_SHOT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("frtm-shots", isDirectory: true)
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func testCaptureDarkTheme() throws {
        let app = launch(theme: "tokyo-night")
        Thread.sleep(forTimeInterval: 8)
        capture(app, named: "debug_dark_launch")
        generateTraffic()
        _ = waitForFlows(app)
        selectFirstFlow(app)
        capture(app, named: "Inspector_dark")
        captureSection(app, title: "Rules", as: "Rules")
        captureSection(app, title: "Collections", as: "Collections")
        captureSection(app, title: "Breakpoints", as: "Breakpoints")
    }

    func testCaptureLightTheme() throws {
        let app = launch(theme: "xcode-light")
        Thread.sleep(forTimeInterval: 8)
        generateTraffic()
        _ = waitForFlows(app)
        selectFirstFlow(app)
        capture(app, named: "Inspector")
    }

    private func launch(theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-hasCompletedOnboarding", "YES",
            "-settings.theme", theme,
            "-settings.autoStart", "YES",
            "-settings.defaultPort", proxyPort,
        ]
        app.launch()
        return app
    }

    @discardableResult
    private func waitForFlows(_ app: XCUIApplication) -> Bool {
        let row = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "typicode", "httpbin")
        ).firstMatch
        return row.waitForExistence(timeout: 40)
    }

    private func generateTraffic() {
        let proxy = "http://127.0.0.1:\(proxyPort)"
        let urls = [
            "https://jsonplaceholder.typicode.com/posts",
            "https://jsonplaceholder.typicode.com/posts/1",
            "https://jsonplaceholder.typicode.com/comments?postId=1",
            "https://httpbin.org/get?feature=map-local&env=demo",
            "https://httpbin.org/status/200",
            "https://httpbin.org/status/404",
            "https://httpbin.org/status/500",
            "https://httpbin.org/json",
            "https://api.github.com/repos/ValentinoPalomba/FRTMProxy",
            "https://dummyjson.com/products?limit=10",
            "https://picsum.photos/id/237/400/300",
            "https://picsum.photos/id/1025/300/300",
        ]
        for url in urls {
            runCurl(proxy: proxy, url: url)
        }
        postJSON(proxy: proxy, url: "https://jsonplaceholder.typicode.com/posts")
    }

    private func runCurl(proxy: String, url: String, extraArguments: [String] = []) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "-o", "/dev/null", "-x", proxy, "-k",
                             "-A", "FRTMProxy-demo/1.0"] + extraArguments + [url]
        try? process.run()
        process.waitUntilExit()
    }

    private func postJSON(proxy: String, url: String) {
        runCurl(proxy: proxy, url: url, extraArguments: [
            "-X", "POST", "-H", "Content-Type: application/json",
            "-d", "{\"title\":\"demo\",\"body\":\"hello\",\"userId\":1}",
        ])
    }

    private func selectFirstFlow(_ app: XCUIApplication) {
        let row = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "typicode", "httpbin")
        ).firstMatch
        if row.exists {
            row.click()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    private func captureSection(_ app: XCUIApplication, title: String, as name: String) {
        let manage = app.buttons["Manage"]
        guard manage.waitForExistence(timeout: 5) else { return }
        manage.click()
        Thread.sleep(forTimeInterval: 0.6)
        let item = app.buttons[title]
        guard item.waitForExistence(timeout: 3) else {
            app.typeKey(.escape, modifierFlags: [])
            return
        }
        item.click()
        Thread.sleep(forTimeInterval: 1.2)
        capture(app, named: name)
        dismissSheet(app)
    }

    private func dismissSheet(_ app: XCUIApplication) {
        for label in ["Close", "Done", "Cancel"] {
            let button = app.buttons[label]
            if button.exists {
                button.click()
                Thread.sleep(forTimeInterval: 0.6)
                return
            }
        }
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let target: XCUIElement = app.windows.firstMatch.exists ? app.windows.firstMatch : app
        let data = target.screenshot().pngRepresentation

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let destination = outputDirectory.appendingPathComponent("\(name).png")
        try? data.write(to: destination)
    }
}
