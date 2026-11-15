import SwiftUI

/// An explicit Back button for a page pushed onto a screen's navigation stack. The automatic one does not always
/// appear in a macOS sheet, so every pushed page adds this instead.
struct BackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

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

extension View {
    /// Adds the Back button to a pushed page.
    func withBackButton() -> some View { modifier(BackButton()) }
}
