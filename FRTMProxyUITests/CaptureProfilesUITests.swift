import XCTest
import Network

final class CaptureProfilesUITests: XCTestCase {
    func testNamedProfilesFilterComposeAndSurviveRelaunch() throws {
        continueAfterFailure = false
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let origin = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "frtm.ui.capture-profile-fixture")
        let ready = expectation(description: "Loopback origin listening")
        origin.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        origin.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let path = request.contains("/one ") ? "one" : "two"
                let body = "{\"path\":\"\(path)\"}"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        origin.start(queue: queue)
        defer { origin.cancel() }
        wait(for: [ready], timeout: 5)
        let originPort = try XCTUnwrap(origin.port?.rawValue)
        let proxyPort = UInt16.random(in: 20000...40000)
        let storage = FileManager.default.temporaryDirectory.appending(path: "frtm-ui-profiles-\(UUID().uuidString)")
        let app = XCUIApplication()
        app.launchEnvironment["FRTM_UI_TEST_STORAGE"] = storage.path
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-hasCompletedOnboarding", "YES", "-settings.autoStart", "YES",
            "-settings.defaultPort", String(proxyPort), "-settings.macosProxyOverride", "NO",
            "-settings.restrictInterceptionToActivePinnedHosts", "NO",
            // Argument-domain values override user pins without writing global preferences.
            "-settings.pinnedHosts", "fixture-empty", "-settings.pinnedApps", "fixture-empty",
            "-inspector.noiseEnabled", "NO", "-settings.theme", "tokyo-night",
            "-settings.interfaceScale", "medium"
        ]
        defer {
            app.terminate()
            let profileSuite = "FRTMProxy.CaptureProfiles.Fixture." + storage.lastPathComponent
            UserDefaults(suiteName: profileSuite)?.removePersistentDomain(forName: profileSuite)
            try? FileManager.default.removeItem(at: storage)
        }
        app.launch()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 45))
        try sendBothPaths(originPort: originPort, proxyPort: proxyPort, queue: queue)
        assertRows(app, one: true, two: true)

        createProfile("Intesa", from: "/one", app: app)
        assertActiveProfile("Intesa", app: app)
        assertRows(app, one: true, two: false)
        capture(app, name: "Profiles_Intesa_one_call")

        selectProfile("All Traffic", app: app)
        assertRows(app, one: true, two: true)
        createProfile("CheBanca", from: "/two", app: app)
        assertRows(app, one: false, two: true)
        selectProfile("Intesa", app: app)
        assertRows(app, one: true, two: false)

        openMembershipMenu(app, path: "/one", scope: "This Host")
        clickVisibleMenuItem("CheBanca", app: app)
        // Adding to another profile must preserve the selected profile.
        assertActiveProfile("Intesa", app: app)
        assertRows(app, one: true, two: false)
        selectProfile("CheBanca", app: app)
        assertRows(app, one: true, two: true)
        capture(app, name: "Profiles_CheBanca_call_or_host")

        app.buttons["Stop"].click()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 45))
        assertActiveProfile("CheBanca", app: app)
        try sendBothPaths(originPort: originPort, proxyPort: proxyPort, queue: queue)
        assertRows(app, one: true, two: true)
        selectProfile("Intesa", app: app)
        assertRows(app, one: true, two: false)
        selectProfile("All Traffic", app: app)
        assertRows(app, one: true, two: true)
        capture(app, name: "Profiles_All_Traffic_after_relaunch")
    }

    private func createProfile(_ name: String, from path: String, app: XCUIApplication) {
        openMembershipMenu(app, path: path, scope: "This Call")
        clickVisibleMenuItem("Create Profile…", app: app)
        let field = app.textFields["capture.profile.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", path, path)).firstMatch.exists, "Creation must include the selected call")
        field.click()
        field.typeText(name)
        let create = app.buttons["capture.profile.create"]
        XCTAssertTrue(create.isEnabled)
        create.click()
    }

    private func openMembershipMenu(_ app: XCUIApplication, path: String, scope: String) {
        let flow = row(app, path: path)
        XCTAssertTrue(flow.waitForExistence(timeout: 8))
        flow.rightClick()
        app.menuItems["Profiles"].click()
        app.menuItems[scope].click()
    }

    private func clickVisibleMenuItem(_ title: String, app: XCUIApplication) {
        // Native AppKit menu items expose action IDs, not nested SwiftUI identifiers.
        // Old submenu children remain in AX; select the currently visible item.
        let candidates = app.menuItems.matching(identifier: title)
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            candidates.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: app)
        guard XCTWaiter.wait(for: [visible], timeout: 5) == .completed,
              let item = candidates.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("No visible menu item: \(title)")
            return
        }
        item.click()
    }

    private func openProfilePicker(_ app: XCUIApplication) -> XCUIElement {
        let picker = app.descendants(matching: .any)["capture.profile.picker"].firstMatch
        if !picker.exists {
            let manage = app.buttons["Manage"]
            XCTAssertTrue(manage.waitForExistence(timeout: 5))
            let advanced = app.buttons["inspector.advancedTools"]
            if !advanced.exists { manage.click() }
            XCTAssertTrue(advanced.waitForExistence(timeout: 5))
            advanced.click()
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        return picker
    }

    private func selectProfile(_ name: String, app: XCUIApplication) {
        openProfilePicker(app).click()
        clickVisibleMenuItem(name, app: app)
        assertActiveProfile(name, app: app)
    }

    private func assertActiveProfile(_ name: String, app: XCUIApplication) {
        let picker = openProfilePicker(app)
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", name), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, "Selected profile should be \(name)")
        // Profile controls live inside Manage; return to the traffic before row/context assertions.
        app.typeKey(.escape, modifierFlags: [])
    }

    private func row(_ app: XCUIApplication, path: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", path)).firstMatch
    }

    private func assertRows(_ app: XCUIApplication, one: Bool, two: Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            row(app, path: "/one").exists == one && row(app, path: "/two").exists == two
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, "Expected /one visible=\(one), /two visible=\(two)")
    }

    private func sendBothPaths(originPort: UInt16, proxyPort: UInt16, queue: DispatchQueue) throws {
        for path in ["one", "two"] {
            let delivered = expectation(description: "Proxied /\(path) returns its fixture body")
            let port = try XCTUnwrap(NWEndpoint.Port(rawValue: proxyPort))
            let client = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            client.stateUpdateHandler = { state in
                if case .ready = state {
                    let request = "GET http://127.0.0.1:\(originPort)/\(path) HTTP/1.1\r\nHost: 127.0.0.1:\(originPort)\r\nConnection: close\r\n\r\n"
                    client.send(content: Data(request.utf8), completion: .contentProcessed { error in
                        XCTAssertNil(error)
                        self.receiveResponse(client, path: path, received: Data(), expectation: delivered)
                    })
                }
            }
            client.start(queue: queue)
            wait(for: [delivered], timeout: 15)
            client.cancel()
        }
    }

    private func receiveResponse(_ connection: NWConnection, path: String, received: Data, expectation: XCTestExpectation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
            var response = received
            response.append(data ?? Data())
            if complete || error != nil {
                XCTAssertNil(error)
                let text = String(decoding: response, as: UTF8.self)
                XCTAssertTrue(text.contains("200 OK"))
                XCTAssertTrue(text.contains("{\"path\":\"\(path)\"}"))
                expectation.fulfill()
            } else {
                self.receiveResponse(connection, path: path, received: response, expectation: expectation)
            }
        }
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
