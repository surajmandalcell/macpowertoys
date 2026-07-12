//
//  MainWindowView.swift
//  powertoys
//

import SwiftUI

struct MainWindowView: View {
    @State private var showAppSettings = false

    var body: some View {
        HomeView()
            .ignoresSafeArea()
            .frame(width: 780, height: 700)
            .background(WindowAccessor())
            .sheet(isPresented: $showAppSettings) {
                AppSettingsSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandOpenSettings)) { _ in
                guard NSApp.keyWindow?.identifier?.rawValue.hasPrefix("main") == true else { return }
                showAppSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openToolSettings)) { notification in
                guard (notification.object as? String) == "home" else { return }
                showAppSettings = true
            }
    }
}

#Preview {
    MainWindowView()
}
