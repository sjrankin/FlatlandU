import SwiftUI

// MARK: - The button bar
//
// Godot sends the buttons as JSON: [{id, title, symbol, selected, menu: [{id, title}]}]. `symbol` is an SF
// Symbol name. A button with a `menu` opens a pop-up menu of entries instead of sending its own id. Tapping a
// button (or a menu entry) sends its id back. The bar lays itself out in as many equal rows as the width needs,
// so every button is always visible, and tells Godot how tall it is (see ToolbarPresenter.swift) so that
// Godot can leave that much room at the bottom of the screen.

/// One entry of a button's pop-up menu (for example "Today's Times…" under More).
struct ToolbarEntry: Identifiable {
    /// The id sent to Godot when the entry is chosen.
    let id: String
    /// The entry's text.
    let title: String
}

/// One button of the bar, from the JSON Godot sends. A button with a menu opens the menu instead of sending its own
/// id.
struct ToolbarButton: Identifiable {
    /// The id sent to Godot when it is tapped.
    let id: String
    /// The text under the icon.
    let title: String
    /// The SF Symbol name of the icon (default "circle").
    let symbol: String
    /// True to draw it in the accent color (a toggle that is on, such as Welcome or Record).
    let selected: Bool
    /// The entries of its pop-up menu; empty for an ordinary button.
    let menu: [ToolbarEntry]
}

/// The button bar's data: the buttons, how many columns they are laid out in, and the callbacks. The bar lays itself
/// out in as many equal rows as the width needs, so every button is always visible; the platform's presenter works
/// the columns out and tells Godot the height.
@MainActor
final class ToolbarModel: ObservableObject {
    /// The buttons, in order; replaced by `update(json:)`.
    @Published private(set) var buttons: [ToolbarButton] = []
    /// How many buttons are in each row now; set by the presenter from the width ([layout(width:count:)]).
    @Published var columns = 1
    /// Called with the id when a button or a menu entry is tapped; FlatlandNativeUI sends it to Godot as
    /// `toolbar_tapped`.
    var onTap: (String) -> Void = { _ in }
    /// The buttons changed (their number may have, which can change the height); the presenter lays out again.
    var onButtonsChanged: () -> Void = {}

    // The Mac bar is more compact: a window is often small, and the bar must not take much of it. Ten buttons fit in
    // one row from about 600 points wide.
    #if os(macOS)
    /// Height of one row of buttons in points (44 on a Mac, where the bar must not take much of a small window; 54 on
    /// iOS).
    static let rowHeight: CGFloat = 44
    /// The narrowest a button may be, in points; decides how many fit in a row (60 on a Mac, 72 on iOS).
    static let minimumCellWidth: CGFloat = 60
    /// Height of the icon in a button, in points.
    static let iconHeight: CGFloat = 20
    #else
    /// Height of one row of buttons in points (44 on a Mac, where the bar must not take much of a small window; 54 on
    /// iOS).
    static let rowHeight: CGFloat = 54
    /// The narrowest a button may be, in points; decides how many fit in a row (60 on a Mac, 72 on iOS).
    static let minimumCellWidth: CGFloat = 72
    /// Height of the icon in a button, in points.
    static let iconHeight: CGFloat = 26
    #endif
    /// Height of the line above the bar, in points.
    static let dividerHeight: CGFloat = 1
    /// On a Mac, buttons are no wider than this, so in a wide window they stay together in the middle.
    static let maximumCellWidth: CGFloat = 110

    /// Works out equal rows: with ten buttons and room for six per row, two rows of five.
    ///
    /// - Parameter width: the usable width in points.
    /// - Parameter count: the number of buttons.
    /// - Returns: the number of columns and rows.
    static func layout(width: CGFloat, count: Int) -> (columns: Int, rows: Int) {
        guard count > 0 else { return (1, 0) }
        let fit = max(1, min(count, Int((width / minimumCellWidth).rounded(.down))))
        let rows = (count + fit - 1) / fit
        return ((count + rows - 1) / rows, rows)
    }

    /// The bar's height for a number of rows.
    ///
    /// - Parameter rows: the number of rows.
    /// - Returns: points: the buttons and the divider (not counting the bottom safe area the bar also covers).
    static func height(rows: Int) -> CGFloat { CGFloat(rows) * rowHeight + dividerHeight }

    /// Replaces the buttons from the JSON Godot sent and tells the presenter. If the JSON cannot be read, nothing
    /// changes.
    ///
    /// - Parameter json: an array of {id, title, symbol, selected, menu: [{id, title}]}.
    func update(json: String) {
        guard let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        buttons = list.compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            let menu = (d["menu"] as? [[String: Any]] ?? []).compactMap { m -> ToolbarEntry? in
                guard let mid = m["id"] as? String else { return nil }
                return ToolbarEntry(id: mid, title: m["title"] as? String ?? mid)
            }
            return ToolbarButton(id: id, title: d["title"] as? String ?? id, symbol: d["symbol"] as? String ?? "circle",
                                 selected: d["selected"] as? Bool ?? false, menu: menu)
        }
        onButtonsChanged()
    }
}

/// The SwiftUI view of the bar: a divider and a grid of buttons (`ToolbarCell`) on the system bar material.
struct ToolbarView: View {
    /// The bar's model.
    @ObservedObject var model: ToolbarModel

    /// The divider and the grid, with a maximum width on a Mac.
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: max(1, model.columns)), spacing: 0) {
                ForEach(model.buttons) { button in
                    ToolbarCell(button: button, onTap: model.onTap)
                }
            }
            #if os(macOS)
            // In a wide window the buttons stay together in the middle instead of spreading across the whole width.
            .frame(maxWidth: ToolbarModel.maximumCellWidth * CGFloat(max(1, model.columns)))
            #endif
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// One button of the bar: an icon above a one-line title (accent colored when selected); a plain button, or a pop-up
/// menu if it has entries.
struct ToolbarCell: View {
    /// The button to draw.
    let button: ToolbarButton
    /// Called with the id of the button or menu entry tapped.
    let onTap: (String) -> Void

    /// The icon and title.
    private var label: some View {
        VStack(spacing: 2) {
            Image(systemName: button.symbol)
                #if os(macOS)
                .font(.body)
                #else
                .font(.title3)
                #endif
                .frame(height: ToolbarModel.iconHeight)
            Text(button.title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(button.selected ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity, minHeight: ToolbarModel.rowHeight, maxHeight: ToolbarModel.rowHeight)
        .contentShape(.rect)
    }

    /// The button or menu around `label`.
    var body: some View {
        if button.menu.isEmpty {
            Button { onTap(button.id) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel(button.title)
        } else {
            Menu {
                ForEach(button.menu) { entry in
                    Button(entry.title) { onTap(entry.id) }
                }
            } label: { label }
            #if os(macOS)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            #endif
            .accessibilityLabel(button.title)
        }
    }
}
