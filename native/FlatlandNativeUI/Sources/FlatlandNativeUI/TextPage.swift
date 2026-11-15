import SwiftUI

/// A page of read-only text (the licenses), opened from a "link" item. It sits in the screen's navigation stack and
/// has an explicit Back button (see BackButton.swift), so the user can return to the screen it was opened from; the
/// usual swipe also works.
struct TextPage: View {
    /// The page's title, shown in the title bar.
    let title: String
    /// The text to show (monospaced, selectable, scrolling).
    let text: String

    /// The scrolling text with the title and the Back button.
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
