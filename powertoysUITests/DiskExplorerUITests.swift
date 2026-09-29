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

        let firstDisk = window.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "diskman.disk."
        )).firstMatch
        if firstDisk.waitForExistence(timeout: 10) {
            firstDisk.click()
            XCTAssertTrue(window.staticTexts["Partition map"].waitForExistence(timeout: 10))
            attach(window.screenshot(), named: "Diskman Normal Modify")
        } else {
            XCTAssertFalse(window.buttons["Manage Disks"].exists)
        }
    }

    @MainActor func testNormalLaunchReviewsMarkedFileWithoutRemovingIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "disk-explorer"]
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Diskman"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        window.buttons["Home Folder"].click()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: window.buttons["Rescan"])
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 180), .completed)

        let tabs = window.descendants(matching: .any)["diskExplorer.resultTabs"]
        tabs.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Largest files")).firstMatch.click()
        let actions = window.buttons["File actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.click()
        app.menuItems["Mark for removal"].click()

        let review = window.buttons["Review 1"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.click()
        XCTAssertTrue(window.staticTexts["Review items"].waitForExistence(timeout: 5))
        let reviewElements = window.descendants(matching: .any)
        let summary = reviewElements["diskman.reviewSummary"]
        XCTAssertTrue(summary.exists)
        let summaryText = "\(summary.label) \(String(describing: summary.value ?? ""))"
        XCTAssertTrue(summaryText.contains("1 item"), summary.debugDescription)
        let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
        XCTAssertTrue(reviewElements.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", home, home
        )).firstMatch.exists)
        XCTAssertTrue(window.buttons["Move to Trash..."].exists)
        XCTAssertTrue(window.buttons["Delete Permanently..."].exists)
        attach(window.screenshot(), named: "Diskman Review Without Deletion")
        window.buttons["Cancel"].click()
        XCTAssertFalse(window.staticTexts["Review items"].exists)
    }

    @MainActor func testModifyActionsAndMergeReviewWithoutWriting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", "disk-explorer"]
        app.launchEnvironment["MACPOWERTOYS_UI_TEST"] = "1"
        app.launch()
        defer { app.terminate() }

        let window = app.windows["Diskman"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let diskRow = window.buttons["diskman.disk.disk91"]
        XCTAssertTrue(diskRow.waitForExistence(timeout: 10))
        diskRow.click()
        let eject = window.buttons["diskman.eject.disk91"]
        XCTAssertTrue(eject.isEnabled)
        eject.click()
        XCTAssertTrue(app.staticTexts["Disk is in use"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Example Editor"].exists)
        XCTAssertFalse(app.buttons["diskman.quitAndEject"].isEnabled)
        XCTAssertFalse(app.buttons["diskman.forceQuitAndEject"].isEnabled)
        attach(app.screenshot(), named: "Diskman Blocked Eject Preview")
        app.buttons["Cancel"].click()
        let diskMapTitle = window.staticTexts["Partition map"]
        XCTAssertTrue(diskMapTitle.waitForExistence(timeout: 20))
        XCTAssertLessThan(diskRow.frame.maxX, diskMapTitle.frame.minX)
        window.buttons["diskman.partition.disk91s2"].click()
        XCTAssertTrue(window.buttons["diskman.lockDisk"].exists)
        XCTAssertTrue(window.staticTexts["Partition and capacity"].exists)
        XCTAssertTrue(window.staticTexts["Volumes and formats"].exists)
        XCTAssertFalse(window.buttons["diskman.action.Resize partition"].isEnabled)
        XCTAssertTrue(window.buttons["diskman.action.Delete partition"].isEnabled)
        XCTAssertFalse(window.buttons["diskman.action.Partition disk"].isEnabled)
        let merge = window.buttons["diskman.action.Merge with next"]
        XCTAssertTrue(merge.isEnabled)
        let firstRow = ["Resize partition", "Rename volume", "Verify"].map {
            window.buttons["diskman.action.\($0)"].frame
        }
        XCTAssertEqual(firstRow[0].minY, firstRow[1].minY, accuracy: 1)
        XCTAssertEqual(firstRow[1].minY, firstRow[2].minY, accuracy: 1)
        attach(window.screenshot(), named: "Diskman Modify Actions")
        merge.click()
        app.buttons["diskman.reviewAction"].click()
        XCTAssertTrue(app.staticTexts["Staged review"].waitForExistence(timeout: 5))
        let consequence = app.descendants(matching: .any)["diskman.mergeConsequence"]
        XCTAssertTrue(consequence.waitForExistence(timeout: 5))
        XCTAssertTrue(consequence.label.contains("ExFAT merge erases both"), consequence.label)
        XCTAssertTrue(app.textFields["diskman.confirmDevice"].exists)
        XCTAssertFalse(app.buttons["diskman.executeAction"].isEnabled)
        attach(app.screenshot(), named: "Diskman Merge Review Preview")
        app.buttons["Discard"].click()
        for _ in 0..<8 where !window.buttons["diskman.map.disk91s3"].isHittable {
            window.scrollViews.firstMatch.swipeDown()
        }
        window.buttons["diskman.map.disk91s3"].click()
        let selectedTarget = window.descendants(matching: .any)["diskman.selectedTarget"]
        XCTAssertTrue(selectedTarget.waitForExistence(timeout: 5))
        XCTAssertTrue(selectedTarget.label.contains("/dev/disk91s3"), selectedTarget.label)
        XCTAssertFalse(merge.isEnabled)
        attach(window.screenshot(), named: "Diskman Map Selection")
        let wholeDisk = window.descendants(matching: .any)["diskman.wholeDisk"]
        XCTAssertTrue(wholeDisk.exists)
        wholeDisk.click()
        XCTAssertTrue(wholeDisk.exists)
        XCTAssertEqual(selectedTarget.label, "Selected whole disk")
        XCTAssertTrue(window.buttons["diskman.action.Partition disk"].isEnabled)
        window.buttons["diskman.partition.disk91s1"].click()
        XCTAssertTrue(window.buttons["diskman.partition.disk91s1"].label.contains("protected"))
        XCTAssertFalse(window.buttons["diskman.action.Delete partition"].isEnabled)
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
        XCTAssertTrue(window.staticTexts["Choose a location"].exists)
        window.buttons["Choose Folder"].firstMatch.click()
        XCTAssertTrue(app.buttons["Browse for folder..."].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
        window.buttons["Home Folder"].click()

        let tabs = window.descendants(matching: .any)["diskExplorer.resultTabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Largest files")).firstMatch.click()
        XCTAssertTrue(window.searchFields["Search largest files"].waitForExistence(timeout: 15))
        attach(window.screenshot(), named: "Diskman Largest Files")
        window.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(window.searchFields["Search Results"].waitForExistence(timeout: 5))
        attach(window.screenshot(), named: "Diskman Results")
        tabs.descendants(matching: .any)["Visualization"].click()
        window.descendants(matching: .any)["Treemap"].click()
        attach(window.screenshot(), named: "Diskman Visualization")
        XCTAssertTrue(window.staticTexts["Space used"].exists)
        XCTAssertTrue(window.staticTexts["Files scanned"].exists)
        attach(app.screenshot(), named: "Diskman Scan Statistics")

        let treemap = window.descendants(matching: .any)
            .matching(identifier: "diskExplorer.treemap").firstMatch
        XCTAssertTrue(treemap.waitForExistence(timeout: 10))
        XCTAssertFalse(window.staticTexts["Point to a block to inspect it"].exists)
        let currentFolder = treemap.label
        let folderTile = treemap.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Library,")).firstMatch
        XCTAssertTrue(folderTile.waitForExistence(timeout: 15))
        let tile = folderTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        tile.hover()
        let hoverDetail = window.descendants(matching: .any)["diskExplorer.hoverDetail"]
        XCTAssertTrue(hoverDetail.waitForExistence(timeout: 5))
        XCTAssertNotNil((hoverDetail.value as? String)?.range(of: #"[0-9]"#, options: .regularExpression),
                        hoverDetail.debugDescription)
        attach(window.screenshot(), named: "Diskman Treemap Hover")
        tile.click()
        XCTAssertEqual(treemap.label, currentFolder)
        tile.doubleClick()
        let drilledFolder = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", currentFolder), object: treemap)
        XCTAssertEqual(XCTWaiter.wait(for: [drilledFolder], timeout: 5), .completed)

        window.descendants(matching: .any)["Rings"].click()
        let rings = window.descendants(matching: .any)
            .matching(identifier: "diskExplorer.rings").firstMatch
        XCTAssertTrue(rings.waitForExistence(timeout: 5))
        XCTAssertFalse(window.staticTexts["Point to a ring to inspect it"].exists)
        rings.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).hover()
        XCTAssertTrue(hoverDetail.waitForExistence(timeout: 5))
        XCTAssertNotNil((hoverDetail.value as? String)?.range(of: #"[0-9]"#, options: .regularExpression),
                        hoverDetail.debugDescription)
        attach(window.screenshot(), named: "Diskman Ring Hover")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
