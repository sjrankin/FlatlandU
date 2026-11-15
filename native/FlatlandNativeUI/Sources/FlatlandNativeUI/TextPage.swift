import SwiftUI

/// A page of read-only text, opened from a `link` item. It sits in the screen's navigation stack, so the system's Back
/// button (and the usual swipe) returns to the screen it was opened from.
struct TextPage: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .withBackButton()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
