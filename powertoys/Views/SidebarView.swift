import SwiftUI

struct SidebarView: View {
    @Binding var selectedCategory: Category

    var body: some View {
        List(selection: $selectedCategory) {
            Section {
                ForEach(Category.allCases.filter { $0.isMainCategory }) { category in
                    Label {
                        Text(category.rawValue)
                    } icon: {
                        Image(systemName: category.icon)
                    }
                    .tag(category)
                }
            }

            Section {
                ForEach(Category.allCases.filter { !$0.isMainCategory }) { category in
                    Label {
                        Text(category.rawValue)
                    } icon: {
                        Image(systemName: category.icon)
                    }
                    .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }
}

#Preview {
    SidebarView(selectedCategory: .constant(.all))
        .frame(width: 200, height: 400)
}
