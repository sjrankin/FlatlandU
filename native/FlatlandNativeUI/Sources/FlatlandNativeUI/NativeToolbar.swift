import SwiftUI

// MARK: - The button bar
//
// Godot sends the buttons as JSON: [{id, title, symbol, selected, menu: [{id, title}]}]. `symbol` is an SF
// Symbol name. A button with a `menu` opens a pop-up menu of entries instead of sending its own id. Tapping a
// button (or a menu entry) sends its id back. The bar lays itself out in as many equal rows as the width needs,
// so every button is always visible, and tells Godot how tall it is (see ToolbarPresenter.swift) so that
// Godot can leave that much room at the bottom of the screen.

struct ToolbarEntry: Identifiable {
    let id: String
    let title: String
}

struct ToolbarButton: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let selected: Bool
    let menu: [ToolbarEntry]
}

@MainActor
final class ToolbarModel: ObservableObject {
    @Published private(set) var buttons: [ToolbarButton] = []
    @Published var columns = 1
    var onTap: (String) -> Void = { _ in }
    /// The buttons changed (their number may have, which can change the height).
    var onButtonsChanged: () -> Void = {}

    // The Mac bar is more compact: a window is often small, and the bar must not take much of it. Ten buttons fit in
    // one row from about 600 points wide.
    #if os(macOS)
    static let rowHeight: CGFloat = 44
    static let minimumCellWidth: CGFloat = 60
    static let iconHeight: CGFloat = 20
    #else
    static let rowHeight: CGFloat = 54
    static let minimumCellWidth: CGFloat = 72
    static let iconHeight: CGFloat = 26
    #endif
    static let dividerHeight: CGFloat = 1
    static let maximumCellWidth: CGFloat = 110

    /// Equal rows: with ten buttons and room for six per row, two rows of five.
    static func layout(width: CGFloat, count: Int) -> (columns: Int, rows: Int) {
        guard count > 0 else { return (1, 0) }
        let fit = max(1, min(count, Int((width / minimumCellWidth).rounded(.down))))
        let rows = (count + fit - 1) / fit
        return ((count + rows - 1) / rows, rows)
    }

    /// Height of the bar's buttons (not counting the bottom safe area it also covers).
    static func height(rows: Int) -> CGFloat { CGFloat(rows) * rowHeight + dividerHeight }

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

struct ToolbarView: View {
    @ObservedObject var model: ToolbarModel

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

struct ToolbarCell: View {
    let button: ToolbarButton
    let onTap: (String) -> Void

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
