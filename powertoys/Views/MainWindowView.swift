import SwiftUI

struct MainWindowView: View {
    @State private var selectedCategory: Category = .all

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $selectedCategory)
        } detail: {
            ContentAreaView(category: selectedCategory)
        }
    }
}

struct ContentAreaView: View {
    let category: Category

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: category.icon)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(category.rawValue)
                .font(.title)
                .foregroundStyle(.primary)

            Text("Coming soon")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    MainWindowView()
        .frame(width: 800, height: 600)
}
