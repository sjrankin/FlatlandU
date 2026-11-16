import SwiftUI

// MARK: - Model

/// The screen being shown. Godot owns the real data; this holds a copy of the description and the values, sends every
/// edit back (`onChange`) and every tap (`onAction`), and accepts new descriptions and values from Godot (`update`,
/// `apply`), which never send anything back. SwiftUI views observe it and redraw when it changes.
@MainActor
final class ScreenModel: ObservableObject {
    /// The current screen description (pages and items).
    @Published private(set) var schema: ScreenSchema
    /// The current value of every control, by key.
    @Published private(set) var values: [String: JSONValue]
    /// Called with the key and new value when the user edits a control; FlatlandNativeUI sends it to Godot as
    /// `value_changed`.
    var onChange: (String, JSONValue) -> Void = { _, _ in }
    /// Called with the id when the user taps an action or a row; sent to Godot as `action_triggered`.
    var onAction: (String) -> Void = { _ in }
    /// Called when the user taps the Done button; closes the sheet.
    var onDone: () -> Void = {}

    /// Creates the model.
    ///
    /// - Parameter schema: the screen description.
    /// - Parameter values: the starting values.
    init(schema: ScreenSchema, values: [String: JSONValue]) {
        self.schema = schema
        self.values = values
    }

    /// The value for a key.
    ///
    /// - Parameter key: the control's key.
    /// - Returns: the value, or an empty string if there is none.
    func value(_ key: String) -> JSONValue { values[key] ?? .string("") }

    /// The user changed something: stores the value and reports it through `onChange`. Does nothing if it is
    /// unchanged.
    ///
    /// - Parameter key: the control's key.
    /// - Parameter value: the new value.
    func set(_ key: String, _ value: JSONValue) {
        guard values[key] != value else { return }
        values[key] = value
        onChange(key, value)
    }

    /// Godot changed one value: stores it without reporting anything back.
    ///
    /// - Parameter key: the control's key.
    /// - Parameter value: the new value.
    func apply(_ key: String, _ value: JSONValue) {
        values[key] = value
    }

    /// Godot sent a new description (the content changed) and values. Navigation inside the screen stays where it is.
    ///
    /// - Parameter schema: the new description.
    /// - Parameter values: the new values.
    func update(schema: ScreenSchema, values: [String: JSONValue]) {
        self.schema = schema
        self.values = values
    }

    /// Creates a two-way binding between a SwiftUI control and a value: reading gives the model's value, writing
    /// calls `set`. There is one for each kind of control: a Bool (toggle), a Double (number), a String (text) and a
    /// Color (stored as "#rrggbb").
    ///
    /// - Parameter key: the value's key (labels: `bool`, `double`, `string` or `color`).
    /// - Returns: the Binding.
    func binding(bool key: String) -> Binding<Bool> {
        Binding(get: { self.value(key).bool }, set: { self.set(key, .bool($0)) })
    }
    /// Creates a two-way binding between a SwiftUI control and a value: reading gives the model's value, writing
    /// calls `set`. There is one for each kind of control: a Bool (toggle), a Double (number), a String (text) and a
    /// Color (stored as "#rrggbb").
    ///
    /// - Parameter key: the value's key (labels: `bool`, `double`, `string` or `color`).
    /// - Returns: the Binding.
    func binding(double key: String) -> Binding<Double> {
        Binding(get: { self.value(key).double }, set: { self.set(key, .number($0)) })
    }
    /// Creates a two-way binding between a SwiftUI control and a value: reading gives the model's value, writing
    /// calls `set`. There is one for each kind of control: a Bool (toggle), a Double (number), a String (text) and a
    /// Color (stored as "#rrggbb").
    ///
    /// - Parameter key: the value's key (labels: `bool`, `double`, `string` or `color`).
    /// - Returns: the Binding.
    func binding(string key: String) -> Binding<String> {
        Binding(get: { self.value(key).string }, set: { self.set(key, .string($0)) })
    }
    /// Creates a two-way binding between a SwiftUI control and a value: reading gives the model's value, writing
    /// calls `set`. There is one for each kind of control: a Bool (toggle), a Double (number), a String (text) and a
    /// Color (stored as "#rrggbb").
    ///
    /// - Parameter key: the value's key (labels: `bool`, `double`, `string` or `color`).
    /// - Returns: the Binding.
    func binding(color key: String) -> Binding<Color> {
        Binding(get: { Color(hex: self.value(key).string) }, set: { self.set(key, .string($0.hexString)) })
    }
}

// MARK: - Screens

/// The top level of a screen. A screen with several pages shows a list of them (as Settings does on iOS), followed by
/// the root items; a screen with one page shows that page directly. It has a Done button.
struct ScreenRoot: View {
    /// The screen's model.
    @ObservedObject var model: ScreenModel

    /// The navigation stack: the page list or the single page, with the title and the Done button.
    var body: some View {
        NavigationStack {
            Group {
                if model.schema.pages.count == 1, let page = model.schema.pages.first {
                    ScreenPageContent(model: model, items: page.items)
                } else {
                    List {
                        Section {
                            ForEach(model.schema.pages) { page in
                                NavigationLink(page.title) { ScreenPageView(model: model, page: page) }
                            }
                        }
                        if !model.schema.rootItems.isEmpty {
                            Section {
                                ForEach(model.schema.rootItems) { item in ScreenRow(model: model, item: item) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(model.schema.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.schema.doneTitle) { model.onDone() }
                }
            }
        }
    }
}

/// A page reached from the list of pages, with an explicit Back button (see BackButton.swift).
struct ScreenPageView: View {
    /// The screen's model.
    @ObservedObject var model: ScreenModel
    /// The page to show.
    let page: ScreenPage

    /// The page's items, looked up again by title, so a screen update while this page is open shows the new content.
    private var items: [ScreenItem] {
        model.schema.pages.first { $0.title == page.title }?.items ?? page.items
    }

    /// The page's content with its title and Back button.
    var body: some View {
        ScreenPageContent(model: model, items: items)
            .navigationTitle(page.title)
            .withBackButton()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

/// The items of one page, grouped under their section headings in a grouped form. A picture first on the page is
/// shown as a banner above the form.
struct ScreenPageContent: View {
    /// The screen's model.
    @ObservedObject var model: ScreenModel
    /// The page's items, in order (section items start a new group).
    let items: [ScreenItem]

    /// One group of items under an optional heading.
    private struct Block: Identifiable {
        /// The group's position, which identifies it for SwiftUI.
        let id: Int
        /// The group's heading, or nil for the first group when the page starts without a section heading.
        var title: String?
        /// The group's items.
        var items: [ScreenItem]
    }

    /// The items split into groups: each "section" item starts a new group. A banner picture, if any, is left out.
    private var blocks: [Block] {
        var out: [Block] = []
        for item in items.dropFirst(banner == nil ? 0 : 1) {
            if item.kind == .section {
                out.append(Block(id: out.count, title: item.title, items: []))
            } else {
                if out.isEmpty { out.append(Block(id: 0, title: nil, items: [])) }
                out[out.count - 1].items.append(item)
            }
        }
        return out
    }

    /// A picture first on the page (About) is shown as a band under the title bar, with the same space above and
    /// below it, instead of as a row of the form (which keeps a wide gap below the title bar).
    private var banner: ScreenItem? { items.first?.kind == .image ? items.first : nil }

    /// The banner (if any) above the form.
    var body: some View {
        VStack(spacing: 0) {
            if let banner {
                ScreenBanner(item: banner)
            }
            form
        }
    }

    /// The form: a section per group. A group without a heading gets no header at all (an empty one still leaves a
    /// gap above the rows).
    private var form: some View {
        Form {
            ForEach(blocks) { block in
                // A block without a heading gets no header at all: an empty one still leaves a gap above the rows.
                if let title = block.title {
                    Section(title) { rows(block) }
                } else {
                    Section { rows(block) }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The rows of one group.
    ///
    /// - Parameter block: the group.
    @ViewBuilder private func rows(_ block: Block) -> some View {
        ForEach(block.items) { item in
            ScreenRow(model: model, item: item)
        }
    }
}

/// The picture at the top of a page, scaled to fit the width on a black band at most 260 points tall. It is read and
/// decoded off the main thread.
struct ScreenBanner: View {
    /// The "image" item (its `path` is the picture's file).
    let item: ScreenItem

    /// The image with its placeholder and padding.
    var body: some View {
        // AsyncImage reads and decodes the file off the main thread.
        AsyncImage(url: URL(fileURLWithPath: item.path)) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Color.clear
        }
        .frame(maxWidth: .infinity, maxHeight: 260)
        .padding(.vertical, 8)
        .background(Color.black)
    }
}

// MARK: - One control, chosen by the kind of item

/// One control, chosen by the kind of item: a toggle, choice, number, color, text field, action button, info row,
/// paragraph, list row, picture or link. An action that has a `confirm` question asks it first.
struct ScreenRow: View {
    /// The screen's model.
    @ObservedObject var model: ScreenModel
    /// The item to draw.
    let item: ScreenItem
    /// True while the confirmation question of an action is showing.
    @State private var confirming = false

    /// The control for the item's kind.
    var body: some View {
        switch item.kind {
        case .toggle:
            Toggle(item.title, isOn: model.binding(bool: item.key))
        case .choice:
            ChoiceRow(model: model, item: item)
        case .number:
            NumberRow(model: model, item: item)
        case .color:
            ColorPicker(item.title, selection: model.binding(color: item.key), supportsOpacity: false)
        case .text:
            LabeledContent(item.title) {
                TextField(item.title, text: model.binding(string: item.key))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
            }
        case .action:
            actionButton
        case .info:
            LabeledContent(item.title) {
                Text(item.detail).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
        case .paragraph:
            ParagraphView(item: item)
        case .row:
            ListRow(model: model, item: item)
        case .image:
            // AsyncImage reads and decodes the file off the main thread.
            AsyncImage(url: URL(fileURLWithPath: item.path)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(maxWidth: .infinity, maxHeight: 260)
            .listRowBackground(Color.black)
        case .link:
            NavigationLink(item.title) { TextPage(title: item.pageTitle.isEmpty ? item.title : item.pageTitle, text: item.detail) }
        case .section:
            EmptyView()
        }
    }

    /// An action button: destructive (red) or prominent (filled, full width) by its style, asking its confirmation
    /// question first if it has one.
    @ViewBuilder private var actionButton: some View {
        let button = Button(item.title, role: item.style == "destructive" ? .destructive : nil) {
            if item.confirm.isEmpty { model.onAction(item.actionId) } else { confirming = true }
        }
        Group {
            if item.style == "prominent" {
                button.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            } else {
                button
            }
        }
        .confirmationDialog(item.confirm, isPresented: $confirming, titleVisibility: .visible) {
            Button(item.title, role: .destructive) { model.onAction(item.actionId) }
        }
    }
}

/// A block of text in one of the styles "title", "headline", "caption", "mono" or the default.
struct ParagraphView: View {
    /// The "paragraph" item.
    let item: ScreenItem

    /// The text, wrapping to as many lines as it needs.
    var body: some View {
        text.fixedSize(horizontal: false, vertical: true)   // wrap to as many lines as the text needs
    }

    /// The text in the item's style.
    @ViewBuilder private var text: some View {
        switch item.style {
        case "title":
            Text(item.title).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .center)
        case "headline":
            Text(item.title).font(.headline)
        case "caption":
            Text(item.title).font(.caption).foregroundStyle(.secondary)
        case "mono":
            Text(item.title).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        default:
            Text(item.title).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// A list row: optional colored dot and leading text (a magnitude), title and subtitle, detail on the right, and either a check box
/// bound to a key or a tap that sends the row's id. A selected row shows a tick; a dimmed one is faded.
struct ListRow: View {
    /// The screen's model.
    @ObservedObject var model: ScreenModel
    /// The "row" item.
    let item: ScreenItem

    /// The row's layout.
    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if !item.dot.isEmpty {
                Circle().fill(Color(hex: item.dot)).frame(width: 10, height: 10)
            }
            if !item.leading.isEmpty {
                Text(item.leading)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(item.accent.isEmpty || !item.dot.isEmpty ? Color.primary : Color(hex: item.accent))
                    .frame(minWidth: 36, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                    if !item.badge.isEmpty {
                        Text(item.badge)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule())
                    }
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !item.detail.isEmpty {
                Text(item.detail).font(.callout.monospacedDigit()).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            if item.selected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .opacity(item.dimmed ? 0.5 : 1)
    }

    /// The row as a toggle (if it has a check key), a button (if it has an action id) or plain content.
    var body: some View {
        if !item.checkKey.isEmpty {
            Toggle(isOn: model.binding(bool: item.checkKey)) { content }
        } else if !item.actionId.isEmpty {
            Button { model.onAction(item.actionId) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// A choice from a list: a pop-up menu for 12 options or fewer, a separate list page (with group headings) for more.
struct ChoiceRow: View {
    /// The screen's model.
    @ObservedObject var model: ScreenModel
    /// The "choice" item.
    let item: ScreenItem

    /// The label of the chosen option (or its value as text if no option matches), shown beside the row for a long
    /// list.
    private var currentLabel: String {
        item.options.first { $0.value == model.value(item.key) }?.label ?? model.value(item.key).string
    }

    /// The picker or the link to the list page.
    var body: some View {
        if item.options.count <= 12 {
            Picker(item.title, selection: Binding(
                get: { model.value(item.key) },
                set: { model.set(item.key, $0) })) {
                ForEach(item.options) { option in Text(option.label).tag(option.value) }
            }
            .pickerStyle(.menu)
        } else {
            NavigationLink {
                ChoiceList(model: model, item: item)
            } label: {
                LabeledContent(item.title, value: currentLabel)
            }
        }
    }
}

/// The list page for a choice with many options, grouped under headings, with a tick on the chosen one and a Back
/// button.
struct ChoiceList: View {
    /// The screen's model.
    @ObservedObject var model: ScreenModel
    /// The "choice" item.
    let item: ScreenItem

    /// The options split into their groups in order of first appearance (options with no group share an unnamed
    /// group).
    private var groups: [(name: String, options: [ScreenOption])] {
        var order: [String] = []
        var byName: [String: [ScreenOption]] = [:]
        for o in item.options {
            let g = o.group ?? ""
            if byName[g] == nil { order.append(g) }
            byName[g, default: []].append(o)
        }
        return order.map { ($0, byName[$0] ?? []) }
    }

    /// The grouped list.
    var body: some View {
        List {
            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.options) { option in
                        Button {
                            model.set(item.key, option.value)
                        } label: {
                            HStack {
                                Text(option.label).foregroundStyle(.primary)
                                Spacer()
                                if option.value == model.value(item.key) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(item.title)
        .withBackButton()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A number: type it in, or use the stepper. The text shows up to four decimals.
struct NumberRow: View {
    /// The screen's model.
    @ObservedObject var model: ScreenModel
    /// The "number" item (minimum, maximum, step and suffix).
    let item: ScreenItem

    /// The label, text field, suffix and stepper.
    var body: some View {
        LabeledContent(item.title) {
            HStack {
                TextField(item.title, value: model.binding(double: item.key), format: .number.precision(.fractionLength(0...4)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                if !item.suffix.isEmpty { Text(item.suffix).foregroundStyle(.secondary) }
                Stepper("", value: model.binding(double: item.key), in: item.minimum...item.maximum, step: item.step)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Colours as "#rrggbb" text, the form Godot's Settings keeps

/// Colors as "#rrggbb" text, the form Godot's Settings keeps.
extension Color {
    /// Makes a Color from "#rrggbb" text.
    ///
    /// - Parameter hex: the text; the "#" is optional. Anything unreadable gives black.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// The color as "#rrggbb" text (lower case), for sending back to Godot.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(iOS)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        let native = NSColor(self)
        (native.usingColorSpace(.sRGB) ?? native).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02x%02x%02x", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
