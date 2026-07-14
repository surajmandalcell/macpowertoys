//
//  AppRuntime.swift
//  powertoys
//

import Foundation

enum AppRuntime {
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || isUITesting
    }

    nonisolated static var isUITesting: Bool {
        ProcessInfo.processInfo.environment["MACPOWERTOYS_UI_TEST"] == "1"
    }
}
