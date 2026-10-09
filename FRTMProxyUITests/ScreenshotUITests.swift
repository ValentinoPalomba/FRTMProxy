import XCTest
import Network

final class ScreenshotUITests: XCTestCase {

    func testComposerHeaderRecovery() throws {
        try verifyComposerHeaderRecovery(theme: "tokyo-night", scale: "medium")
    }

    func testComposerVisualMatrix() throws {
        for theme in ["tokyo-night", "xcode-light"] {
            for scale in ["small", "medium", "large"] {
                try verifyComposerHeaderRecovery(theme: theme, scale: scale)
            }
        }
    }

    private func verifyComposerHeaderRecovery(theme: String, scale: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let fixture = try NWListener(using: parameters)
        let ready = expectation(description: "Local header fixture listening")
        let received = expectation(description: "Fixture received duplicate and empty headers")
        fixture.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        let queue = DispatchQueue(label: "frtm.ui.header-fixture")
        fixture.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                if request.contains("X-Repeated: one\r\n"), request.contains("X-Repeated: two\r\n"), request.contains("X-Empty:\r\n") || request.contains("X-Empty: \r\n") {
                    received.fulfill()
                }
                let body = Data(#"{"echo":"one two"}"#.utf8)
                var response = Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        fixture.start(queue: queue)
        defer { fixture.cancel() }
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(fixture.port?.rawValue)
        let app = XCUIApplication()
        let storage = FileManager.default.temporaryDirectory.appending(path: "frtm-ui-capture-\(UUID().uuidString)")
        app.launchEnvironment["FRTM_UI_TEST_STORAGE"] = storage.path
        defer { try? FileManager.default.removeItem(at: storage) }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-hasCompletedOnboarding", "YES", "-settings.autoStart", "NO", "-settings.theme", theme, "-settings.interfaceScale", scale]
        app.launch()
        app.menuBars.menuBarItems["Tools"].click()
        app.menuItems["Compose Request…"].click()
        let headerTab = app.buttons["composer.request.headers"]
        XCTAssertTrue(headerTab.waitForExistence(timeout: 5))
        headerTab.click()
        let add = app.buttons["Add Header"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.click()
        let keys = app.textFields.matching(NSPredicate(format: "label == %@", "Request header name"))
        XCTAssertEqual(keys.count, 1)
        // Typing immediately checks that Add Header focuses the new name.
        app.typeText("X-Repeated")
        let values = app.textFields.matching(NSPredicate(format: "label == %@", "Request header value"))
        values.element(boundBy: 0).click()
        app.typeText("one")
        add.click()
        XCTAssertEqual(keys.count, 2)
        app.typeText("X-Repeated")
        values.element(boundBy: 1).click()
        app.typeText("two")
        add.click()
        XCTAssertEqual(keys.count, 3)
        app.typeText("X-Empty")
        let url = app.textFields["https://example.com/api/endpoint"]
        url.click()
        app.typeText("http://127.0.0.1:\(port)/headers")
        capture(app, named: "Composer_headers_recovery_\(theme)_\(scale)")
        XCTAssertTrue(app.buttons["Send"].isHittable, "Send must remain visible with header rows")
        app.buttons["Send"].click()
        if app.buttons["Response"].exists { app.buttons["Response"].click() }
        let echoed = app.descendants(matching: .any)["composer.response.body"]
        XCTAssertTrue(echoed.waitForExistence(timeout: 10))
        XCTAssertTrue((echoed.value as? String ?? echoed.label).contains("one two"), "The fixture response must be visible")
        wait(for: [received], timeout: 5)
        XCTAssertTrue(app.buttons["Send"].isHittable, "Send must remain visible in Response")
        capture(app, named: "Composer_headers_response_\(theme)_\(scale)")
        app.buttons["Variables"].click()
        app.buttons["Add Variable"].click()
        app.typeText("TOKEN")
        app.buttons["Cancel"].click()
        app.buttons["Variables"].click()
        XCTAssertEqual(app.textFields.matching(NSPredicate(format: "label == %@", "Variable name")).count, 0, "Cancel must discard variable edits")
        app.buttons["Add Variable"].click()
        app.typeText("TOKEN")
        app.secureTextFields["Variable value"].click()
        app.typeText("fixture-value")
        capture(app, named: "Composer_variables_recovery_\(theme)_\(scale)")
        app.buttons["Save"].click()
        app.buttons["Variables"].click()
        XCTAssertEqual(app.textFields["Variable name"].value as? String, "TOKEN")
        app.buttons["Cancel"].click()
        app.buttons["Close"].click()
        app.terminate()
    }

    func testRuleMatcherHeaderRecovery() throws {
        for theme in ["tokyo-night", "xcode-light"] {
            let app = XCUIApplication()
            let storage = FileManager.default.temporaryDirectory.appending(path: "frtm-ui-rules-\(UUID().uuidString)")
            app.launchEnvironment["FRTM_UI_TEST_STORAGE"] = storage.path
            defer { try? FileManager.default.removeItem(at: storage) }
            app.launchArguments = ["-AppleLanguages", "(en)", "-hasCompletedOnboarding", "YES", "-settings.autoStart", "NO", "-settings.theme", theme, "-settings.interfaceScale", "medium"]
            app.launch()
            app.menuBars.menuBarItems["Rules"].click()
            app.menuItems["Traffic Rules…"].click()
            let addRule = app.buttons["Add Rule"]
            XCTAssertTrue(addRule.waitForExistence(timeout: 5))
            addRule.click()
            app.buttons["Add Header"].click()
            XCTAssertFalse(app.buttons["Save Rule"].isEnabled, "An unnamed matcher must block saving")
            app.typeText("X-Environment")
            let pattern = app.textFields["Header matcher pattern"]
            pattern.click()
            app.typeText("stage*")
            app.popUpButtons.matching(NSPredicate(format: "label CONTAINS %@", "Header matcher mode")).firstMatch.click()
            app.menuItems["wildcard"].click()
            app.checkBoxes["Case sensitive"].click()
            capture(app, named: "Rule_matcher_\(theme)")
            XCTAssertTrue(app.buttons["Save Rule"].isEnabled)
            app.buttons["Save Rule"].click()
            app.buttons["Edit Rule"].click()
            XCTAssertEqual(app.textFields["Header matcher name"].value as? String, "X-Environment")
            XCTAssertEqual(app.textFields["Header matcher pattern"].value as? String, "stage*")
            XCTAssertEqual(app.popUpButtons.matching(NSPredicate(format: "label CONTAINS %@", "Header matcher mode")).firstMatch.value as? String, "wildcard")
            XCTAssertEqual((app.checkBoxes["Case sensitive"].value as? NSNumber)?.boolValue, false)
            capture(app, named: "Rule_matcher_reopened_\(theme)")
            app.typeKey(.escape, modifierFlags: [])
            // Cancel the document draft; no fixture rule is applied to capture.
            app.buttons["Cancel"].click()
            openHeaderColumns(app)
            capture(app, named: "Header_columns_\(theme)")
            let columnName = app.textFields["Header name, e.g. X-Request-ID"]
            columnName.click()
            app.typeText("X-Recovery-Cancel")
            app.buttons["Add"].click()
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "X-Recovery-Cancel", "X-Recovery-Cancel")).firstMatch.exists)
            XCTAssertEqual(columnName.value as? String, "")
            app.typeKey(.escape, modifierFlags: [])
            openHeaderColumns(app)
            XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "X-Recovery-Cancel", "X-Recovery-Cancel")).firstMatch.exists)
            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }

    private func openHeaderColumns(_ app: XCUIApplication) {
        let fields = app.descendants(matching: .any).matching(identifier: "Table fields").firstMatch
        XCTAssertTrue(fields.waitForExistence(timeout: 5))
        fields.click()
        let addField = app.menuItems["Add Field…"]
        XCTAssertTrue(addField.waitForExistence(timeout: 5))
        addField.click()
        XCTAssertTrue(app.textFields["Header name, e.g. X-Request-ID"].waitForExistence(timeout: 5))
    }

    func testInspectorDiffAndSessionNotes() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let fixture = try NWListener(using: parameters)
        let ready = expectation(description: "Inspector fixture ready")
        fixture.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        fixture.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
                let body = request.contains("/first") ? "{\"id\":1,\"message\":\"first\"}" : "{\"id\":2,\"message\":\"second\"}"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        fixture.start(queue: .global())
        defer { fixture.cancel() }
        wait(for: [ready], timeout: 5)
        let origin = try XCTUnwrap(fixture.port)
        for theme in ["tokyo-night", "xcode-light"] {
            let app = XCUIApplication()
            let storage = FileManager.default.temporaryDirectory.appending(path: "frtm-ui-inspector-\(UUID().uuidString)")
            app.launchEnvironment["FRTM_UI_TEST_STORAGE"] = storage.path
            defer { try? FileManager.default.removeItem(at: storage) }
            let capturePort = UInt16.random(in: 20000...40000)
            app.launchArguments = ["-AppleLanguages", "(en)", "-hasCompletedOnboarding", "YES", "-settings.autoStart", "YES", "-settings.defaultPort", String(capturePort), "-settings.macosProxyOverride", "NO", "-settings.restrictInterceptionToActivePinnedHosts", "NO", "-inspector.noiseEnabled", "NO", "-settings.theme", theme, "-settings.interfaceScale", "medium"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 45))
            for path in ["first", "second"] {
                let delivered = expectation(description: "Proxied \(path) response")
                let client = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: capturePort)!, using: .tcp)
                client.stateUpdateHandler = { state in
                    if case .ready = state {
                        let request = "GET http://127.0.0.1:\(origin)/\(path) HTTP/1.1\r\nHost: 127.0.0.1:\(origin)\r\nConnection: close\r\n\r\n"
                        client.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                            client.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                                XCTAssertNil(error)
                                XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.contains("200 OK") == true)
                                delivered.fulfill()
                                client.cancel()
                            }
                        })
                    }
                }
                client.start(queue: .global())
                wait(for: [delivered], timeout: 15)
                client.cancel()
            }
            let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "/first")).firstMatch
            let second = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "/second")).firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 8))
            first.click()
            capture(app, named: "Inspector_capture_\(theme)")
            XCTAssertTrue(app.buttons["Stop"].isHittable)
            XCTAssertTrue(app.buttons["Manage"].isHittable)
            app.buttons["Stop"].click()
            app.menuBars.menuBarItems["Capture"].click()
            app.menuItems["Sessions…"].click()
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
            let sessionRow = app.sheets.firstMatch.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "/first")).firstMatch
            XCTAssertTrue(sessionRow.waitForExistence(timeout: 8))
            capture(app, named: "Session_timeline_\(theme)")
            app.buttons["Import HAR…"].click()
            XCTAssertTrue(app.buttons["Choose HAR File…"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Import"].isEnabled)
            capture(app, named: "Session_import_empty_\(theme)")
            app.typeKey(.escape, modifierFlags: [])
            sessionRow.rightClick()
            app.menuItems["Edit Note"].click()
            capture(app, named: "Session_note_\(theme)")
            let note = app.textViews["Flow note"]
            note.click()
            for character in "Recovery note" { note.typeText(String(character)) }
            XCTAssertEqual(note.value as? String, "Recovery note")
            app.buttons["Save"].click()
            sessionRow.rightClick()
            app.menuItems["Edit Note"].click()
            XCTAssertEqual(note.value as? String, "Recovery note")
            app.typeKey(.escape, modifierFlags: [])
            app.buttons["Close"].click()
            first.click()
            XCUIElement.perform(withKeyModifiers: .command) { second.click() }
            XCTAssertTrue(app.staticTexts["Compare flows"].waitForExistence(timeout: 5))
            capture(app, named: "Inspector_diff_\(theme)")
            app.buttons["Close"].click()
            app.terminate()
        }
    }

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
        let target: XCUIElement
        if app.sheets.count > 0 { target = app.sheets.element(boundBy: app.sheets.count - 1) }
        else { target = app.windows.firstMatch.exists ? app.windows.firstMatch : app }
        let data = target.screenshot().pngRepresentation

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let destination = outputDirectory.appendingPathComponent("\(name).png")
        try? data.write(to: destination)
    }
}
