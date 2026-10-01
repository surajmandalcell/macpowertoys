import AppKit
import Observation
import SwiftUI
import XCTest
@testable import OnePlusUI

@MainActor
final class OnePlusRetainedPageTests: XCTestCase {
    func testVisitedPageKeepsStateWithoutHiddenObservationOrSelectionRebuilds() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let model = RetainedPageModel()
        model.visible = false
        let probe = RetainedPageProbe()
        let host = NSHostingView(rootView: AnyView(RetainedPageFixture(model: model, probe: probe)))
        host.frame.size = CGSize(width: 480, height: 300)
        func settle() {
            autoreleasepool {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                host.layoutSubtreeIfNeeded()
            }
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, foreground)
        }

        host.rootView = AnyView(RetainedPageFixture(model: model, probe: probe, retains: false))
        model.visible = true
        model.selected = true
        settle()
        let baselineBuilds = probe.builds
        for _ in 0..<20 { model.selectionNoise += 1; settle() }
        XCTAssertEqual(probe.builds - baselineBuilds, 20)
        host.rootView = AnyView(EmptyView())
        settle()
        model.selected = false
        model.visible = false
        probe.builds = 0
        host.rootView = AnyView(RetainedPageFixture(model: model, probe: probe))
        settle()
        XCTAssertEqual(probe.builds, 0, "Unvisited pages must stay lazy")
        model.selected = true
        settle()
        weak var retainedHost: NSView?
        autoreleasepool {
            retainedHost = descendants(host).dropFirst().first { $0 is NSHostingView<AnyView> }
        }
        XCTAssertNotNil(retainedHost)
        let token = try XCTUnwrap(probe.token)
        XCTAssertGreaterThan(probe.builds, 0, "Cold hidden hosts need a complete first frame")
        XCTAssertFalse(probe.visible)
        XCTAssertEqual(probe.runningTasks, 0)
        model.visible = true
        settle()
        XCTAssertEqual(probe.runningTasks, 1)
        let builds = probe.builds
        for _ in 0..<20 { model.selectionNoise += 1; settle() }
        XCTAssertEqual(probe.builds - builds, 0, "Selection must stay outside content equality")
        model.sample = 1
        settle()
        XCTAssertEqual(probe.sample, 1, "Visible observations must still update")

        model.selected = false
        settle()
        XCTAssertFalse(probe.visible, "Deliver hidden visibility before detaching")
        XCTAssertEqual(probe.runningTasks, 0)
        let hiddenBuilds = probe.builds
        for value in 2...21 { model.sample = value; settle() }
        XCTAssertEqual(probe.builds - hiddenBuilds, 0, "Hidden pages must drop live observations")
        model.revision = 1
        settle()
        model.selected = true
        settle()
        XCTAssertEqual(probe.token, token, "Return must preserve page state")
        XCTAssertEqual(probe.sample, 21, "Return must read the latest sample")
        XCTAssertEqual(probe.revision, 1, "Changed content inputs must reach the retained page")
        XCTAssertTrue(probe.visible)
        XCTAssertEqual(probe.runningTasks, 1)
        for _ in 0..<10 {
            model.selected = false; settle()
            model.selected = true; settle()
            XCTAssertEqual(probe.token, token)
        }

        model.visible = false
        settle()
        XCTAssertFalse(probe.visible)
        XCTAssertEqual(probe.runningTasks, 0)
        let coveredBuilds = probe.builds
        model.sample = 22
        settle()
        XCTAssertEqual(probe.builds, coveredBuilds)
        model.visible = true
        settle()
        XCTAssertEqual(probe.sample, 22)
        host.rootView = AnyView(EmptyView())
        settle()
        XCTAssertNil(retainedHost, "Removing the owning graph must release the cached host")
        XCTAssertEqual(probe.runningTasks, 0)
        print("Retained page: selection rebuilds before=20/20 after=0/20; hidden=0/20; state preserved=10/10")
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

@MainActor @Observable private final class RetainedPageModel {
    var selected = false
    var visible = true
    var selectionNoise = 0
    var revision = 0
    var sample = 0
}

@MainActor private final class RetainedPageProbe {
    var builds = 0
    var token: UUID?
    var sample = -1
    var revision = -1
    var visible = false
    var runningTasks = 0
}

private struct RetainedPageFixture: View {
    let model: RetainedPageModel
    let probe: RetainedPageProbe
    var retains = true

    var body: some View {
        let _ = model.selectionNoise
        let revision = model.revision
        Group {
            if retains {
                OnePlusRetainedPage(isSelected: model.selected, revision: revision) {
                    let _ = { probe.builds += 1 }()
                    RetainedPageLeaf(sample: model.sample, revision: revision, probe: probe)
                }
            } else if model.selected {
                let _ = { probe.builds += 1 }()
                RetainedPageLeaf(sample: model.sample, revision: revision, probe: probe)
            }
        }
        .environment(\.onePlusIsVisible, model.visible)
    }
}

private struct RetainedPageLeaf: View {
    let sample: Int
    let revision: Int
    let probe: RetainedPageProbe
    @Environment(\.onePlusIsVisible) private var visible
    @State private var token = UUID()

    var body: some View {
        let _ = { probe.token = token; probe.sample = sample; probe.revision = revision }()
        Text("Sample \(sample)")
            .onChange(of: visible, initial: true) { _, value in probe.visible = value }
            .task(id: visible) {
                guard visible else { return }
                probe.runningTasks += 1
                defer { probe.runningTasks -= 1 }
                try? await Task.sleep(for: .seconds(60))
            }
    }
}
