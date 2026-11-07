import SwiftUI

struct ContentStatusPicker: View {
    @Binding var selection: ContentStatusFilter
    let counts: [ContentStatusFilter: Int]

    var body: some View {
        Picker("内容状态", selection: $selection) {
            ForEach(ContentStatusFilter.allCases) { status in
                Text("\(status.title) \(counts[status, default: 0])").tag(status)
            }
        }
        .pickerStyle(.segmented)
    }
}
