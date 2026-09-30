import OnePlusUI
import SwiftUI

struct PageRegionsShowcase<Header: View>: View {
    let header: Header
    @State private var query = ""
    @State private var selection = Set<String>()
    @State private var sortColumn = 0
    @State private var ascending = true
    @State private var detail = "Scroll the table. This inspector, toolbar, and footer stay in place."
    @State private var rows = (1...1000).map {
        OnePlusTableItem(id: String($0), cells: ["Process \($0)", String($0), "Running"], symbol: "app")
    }

    var body: some View {
        let visible = rows.filter { query.isEmpty || $0.cells[0].localizedCaseInsensitiveContains(query) }
        OnePlusPage(scrolls: false) {
            header
        } toolbar: {
            HStack(spacing: 16) {
                OnePlusSearchField(prompt: "Find a process", text: $query)
                OnePlusStatus("Toolbar stays fixed")
            }
        } footer: {
            HStack {
                OnePlusStatus("\(visible.count) processes")
                Spacer()
                Text("\(selection.count) selected").onePlusText(.mono)
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                OnePlusCard {
                    OnePlusCardHeader("Processes")
                    OnePlusNativeTable(columns: [.init("Name", width: 240), .init("PID", width: 90),
                                                  .init("Status", width: 120)],
                                       rows: visible, selection: $selection, sortColumn: sortColumn, ascending: ascending,
                                       sort: { column, direction in
                                           sortColumn = column; ascending = direction
                                           rows.sort { direction ? $0.cells[column] < $1.cells[column] : $0.cells[column] > $1.cells[column] }
                                       }, open: { detail = "Opened process IDs: " + $0.sorted().joined(separator: ", ") },
                                       preview: { detail = "Preview process IDs: " + $0.sorted().joined(separator: ", ") },
                                       remove: { ids in rows.removeAll { ids.contains($0.id) }; selection.subtract(ids) },
                                       actions: { _ in [] })
                }
                OnePlusCard {
                    OnePlusCardHeader("Inspector")
                    VStack(alignment: .leading, spacing: 16) {
                        Text(detail)
                            .onePlusText(.row)
                        OnePlusKeyValueRow("Title top", value: "16 pt")
                        OnePlusKeyValueRow("Content gap", value: "16 pt")
                    }.padding(16)
                }.frame(width: 220)
            }
        }
    }
}
