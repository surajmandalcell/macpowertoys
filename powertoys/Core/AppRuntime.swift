//
//  AppRuntime.swift
//  powertoys
//

import Foundation

enum AppRuntime {
    nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    nonisolated static var isRunningTests: Bool {
        isRunningUnitTests || isUITesting
    }

    nonisolated static var isUITesting: Bool {
        ProcessInfo.processInfo.environment["MACPOWERTOYS_UI_TEST"] == "1"
    }
}
