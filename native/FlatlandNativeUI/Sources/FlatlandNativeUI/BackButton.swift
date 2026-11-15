import SwiftUI

/// A view modifier that gives a page pushed onto a screen's navigation stack an explicit Back button (a chevron and
/// the word "Back") and hides the automatic one, which does not always appear in a macOS sheet. Use it through
/// `withBackButton()`.
struct BackButton: ViewModifier {
    /// The environment action that pops the page off the navigation stack.
    @Environment(\.dismiss) private var dismiss

    /// The content with the system Back button hidden and ours in its place (top left).
    ///
    /// - Parameter content: the page being modified.
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Back", systemImage: "chevron.backward") { dismiss() }
                }
            }
    }
}

/// Adds the Back button modifier to any view.
extension View {
    /// Adds the Back button to a pushed page.
    ///
    /// - Returns: the modified view.
    func withBackButton() -> some View { modifier(BackButton()) }
}
