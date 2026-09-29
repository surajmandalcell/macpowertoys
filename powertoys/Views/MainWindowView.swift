import SwiftUI
import OnePlusUI

struct MainWindowView: View {
    var body: some View {
        HomeView()
            .background(WindowAccessor(identifier: "main"))
    }
}

#Preview { MainWindowView() }
