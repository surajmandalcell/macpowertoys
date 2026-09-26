import XCTest

final class DiskExplorerUITests: XCTestCase {
    @MainActor func testNormalLaunchOpensDiskmanWithoutTestMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "disk-explorer"]
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Diskman"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        XCTAssertTrue(window.descendants(matching: .any)["diskExplorer.scan"].waitForExistence(timeout: 10))
        attach(window.screenshot(), named: "Diskman Normal Launch")

        window.buttons["Manage Disks"].click()
        XCTAssertTrue(window.staticTexts["Modify"].waitForExistence(timeout: 10))
        XCTAssertFalse(window.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] 'chart updates live'"
        )).firstMatch.exists)
        attach(window.screenshot(), named: "Diskman Normal Modify")
    }

    @MainActor func testNormalLaunchReviewsMarkedFileWithoutRemovingIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "disk-explorer"]
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Diskman"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        XCTAssertTrue(window.buttons["Rescan"].waitForExistence(timeout: 30))

        let tabs = window.descendants(matching: .any)["diskExplorer.resultTabs"]
        tabs.descendants(matching: .any)["Largest Files"].click()
        let mark = window.buttons.matching(identifier: "Mark for Removal").firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        mark.click()

        let review = window.buttons["Review 1"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.click()
        XCTAssertTrue(window.staticTexts["Review Items"].waitForExistence(timeout: 5))
        let reviewElements = window.descendants(matching: .any)
        let summary = reviewElements["diskman.reviewSummary"]
        XCTAssertTrue(summary.exists)
        let summaryText = "\(summary.label) \(String(describing: summary.value ?? ""))"
        XCTAssertTrue(summaryText.contains("1 item"), summary.debugDescription)
        let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
        XCTAssertTrue(reviewElements.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", home, home
        )).firstMatch.exists)
        XCTAssertTrue(window.buttons["Move to Trash"].exists)
        XCTAssertTrue(window.buttons["Delete Permanently…"].exists)
        attach(window.screenshot(), named: "Diskman Review Without Deletion")
        window.buttons["Cancel"].click()
        XCTAssertFalse(window.staticTexts["Review Items"].exists)
    }

    @MainActor func testModifyShowsPhysicalDisksWithoutWriting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "disk-explorer"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Diskman"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        window.buttons["Manage Disks"].click()
        let firstDisk = window.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'diskman.disk.'"
        )).firstMatch
        if firstDisk.waitForExistence(timeout: 10) {
            firstDisk.click()
            XCTAssertTrue(window.staticTexts["DISK MAP"].waitForExistence(timeout: 20))
            XCTAssertTrue(window.staticTexts["PARTITION & CAPACITY"].exists)
            XCTAssertTrue(window.staticTexts["VOLUMES & FORMATS"].exists)
            XCTAssertTrue(window.buttons["diskman.action.Resize partition"].exists)
            XCTAssertTrue(window.buttons["diskman.action.Merge with next"].exists)
            XCTAssertTrue(window.buttons["diskman.action.Delete partition"].exists)
            let firstPartition = window.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH 'diskman.partition.'"
            )).firstMatch
            if firstPartition.exists {
                firstPartition.click()
                XCTAssertTrue(window.buttons["Whole disk"].waitForExistence(timeout: 5))
                window.buttons["Whole disk"].click()
            }
            attach(window.screenshot(), named: "Diskman Modify")
        } else {
            XCTAssertTrue(window.staticTexts["No Physical Disks"].exists)
            XCTAssertFalse(window.descendants(matching: .any)["diskman.inventoryError"].exists)
            attach(window.screenshot(), named: "Diskman Modify Empty")
        }
    }

    @MainActor func testScanControlsAndResultTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "disk-explorer"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Diskman"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        XCTAssertTrue(window.descendants(matching: .any)["diskExplorer.scan"].waitForExistence(timeout: 5))
        let contents = window.buttons["diskExplorer.contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.click()
        XCTAssertTrue(window.textFields["Search Contents"].waitForExistence(timeout: 5))
        contents.click()
        XCTAssertFalse(window.textFields["Search Contents"].exists)

        let tabs = window.descendants(matching: .any)["diskExplorer.resultTabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.descendants(matching: .any)["Largest Files"].click()
        XCTAssertTrue(window.textFields["Filter largest files"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Diskman Largest Files")
        tabs.descendants(matching: .any)["Visualization"].click()
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Diskman Visualization")

        let statistics = window.buttons["diskExplorer.statistics"]
        XCTAssertTrue(statistics.waitForExistence(timeout: 5))
        statistics.click()
        XCTAssertTrue(app.staticTexts["Measured So Far"].waitForExistence(timeout: 5)
                      || app.staticTexts["Scan Statistics"].exists)
        attach(app.screenshot(), named: "Diskman Scan Statistics")
        statistics.click()

        let treemap = window.descendants(matching: .any)
            .matching(identifier: "diskExplorer.treemap").firstMatch
        XCTAssertTrue(treemap.waitForExistence(timeout: 10))
        let treemapDetails = window.descendants(matching: .any)["diskExplorer.treemapDetails"]
        XCTAssertTrue(treemapDetails.exists)
        XCTAssertGreaterThanOrEqual(treemapDetails.frame.minY, treemap.frame.maxY - 2)
        XCTAssertEqual(treemapDetails.label, "Point to a block to inspect it")
        let currentFolder = treemap.label
        let tile = treemap.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
        tile.hover()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", "Point to a block to inspect it"),
            object: treemapDetails
        )], timeout: 5), .completed)
        XCTAssertNotNil(treemapDetails.label.range(of: #", [0-9]"#, options: .regularExpression))
        attach(window.screenshot(), named: "Diskman Treemap Hover")
        tile.click()
        let drilledFolder = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", currentFolder), object: treemap)
        XCTAssertEqual(XCTWaiter.wait(for: [drilledFolder], timeout: 5), .completed)

        window.descendants(matching: .any)["Rings"].click()
        let rings = window.descendants(matching: .any)
            .matching(identifier: "diskExplorer.rings").firstMatch
        XCTAssertTrue(rings.waitForExistence(timeout: 5))
        let ringDetails = window.descendants(matching: .any)["diskExplorer.ringDetails"]
        XCTAssertTrue(ringDetails.exists)
        XCTAssertGreaterThanOrEqual(ringDetails.frame.minY, rings.frame.maxY - 2)
        XCTAssertEqual(ringDetails.label, "Point to a ring to inspect it")
        rings.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).hover()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", "Point to a ring to inspect it"),
            object: ringDetails
        )], timeout: 5), .completed)
        XCTAssertNotNil(ringDetails.label.range(of: #", [0-9]"#, options: .regularExpression))
        attach(window.screenshot(), named: "Diskman Ring Hover")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
