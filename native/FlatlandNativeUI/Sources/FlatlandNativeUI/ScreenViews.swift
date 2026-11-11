import SwiftUI

// MARK: - Model

/// The screen being shown. Godot owns the real data; this holds a copy of the description and the values,
/// sends every edit back (`onChange`) and every tap (`onAction`), and accepts new descriptions and values
/// from Godot (`update`, `apply`), which never send anything back.
@MainActor
final class ScreenModel: ObservableObject {
    @Published private(set) var schema: ScreenSchema
    @Published private(set) var values: [String: JSONValue]
    var onChange: (String, JSONValue) -> Void = { _, _ in }
    var onAction: (String) -> Void = { _ in }
    var onDone: () -> Void = {}

    init(schema: ScreenSchema, values: [String: JSONValue]) {
        self.schema = schema
        self.values = values
    }

    func value(_ key: String) -> JSONValue { values[key] ?? .string("") }

    /// The user changed something.
    func set(_ key: String, _ value: JSONValue) {
        guard values[key] != value else { return }
        values[key] = value
        onChange(key, value)
    }

    /// Godot changed one value.
    func apply(_ key: String, _ value: JSONValue) {
        values[key] = value
    }

    /// Godot sent a new description (the content changed) and values. Navigation stays where it is.
    func update(schema: ScreenSchema, values: [String: JSONValue]) {
        self.schema = schema
        self.values = values
    }

    func binding(bool key: String) -> Binding<Bool> {
        Binding(get: { self.value(key).bool }, set: { self.set(key, .bool($0)) })
    }
    func binding(double key: String) -> Binding<Double> {
        Binding(get: { self.value(key).double }, set: { self.set(key, .number($0)) })
    }
    func binding(string key: String) -> Binding<String> {
        Binding(get: { self.value(key).string }, set: { self.set(key, .string($0)) })
    }
    func binding(color key: String) -> Binding<Color> {
        Binding(get: { Color(hex: self.value(key).string) }, set: { self.set(key, .string($0.hexString)) })
    }
}

// MARK: - Screens

/// The top level. A screen with several pages shows a list of them (as Settings does on iOS); a screen with
/// one page shows that page directly.
struct ScreenRoot: View {
    @ObservedObject var model: ScreenModel

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

/// A page reached from the list of pages.
struct ScreenPageView: View {
    @ObservedObject var model: ScreenModel
    let page: ScreenPage

    /// Look the page up again by title, so a screen update while this page is open shows the new content.
    private var items: [ScreenItem] {
        model.schema.pages.first { $0.title == page.title }?.items ?? page.items
    }

    var body: some View {
        ScreenPageContent(model: model, items: items)
            .navigationTitle(page.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

/// The items of one page, grouped under their section headings.
struct ScreenPageContent: View {
    @ObservedObject var model: ScreenModel
    let items: [ScreenItem]

    private struct Block: Identifiable {
        let id: Int
        var title: String?
        var items: [ScreenItem]
    }

    private var blocks: [Block] {
        var out: [Block] = []
        for item in items {
            if item.kind == .section {
                out.append(Block(id: out.count, title: item.title, items: []))
            } else {
                if out.isEmpty { out.append(Block(id: 0, title: nil, items: [])) }
                out[out.count - 1].items.append(item)
            }
        }
        return out
    }

    var body: some View {
        Form {
            ForEach(blocks) { block in
                Section(block.title ?? "") {
                    ForEach(block.items) { item in
                        ScreenRow(model: model, item: item)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - One control, chosen by the kind of item

struct ScreenRow: View {
    @ObservedObject var model: ScreenModel
    let item: ScreenItem
    @State private var confirming = false

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
        case .section:
            EmptyView()
        }
    }

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

struct ParagraphView: View {
    let item: ScreenItem

    var body: some View {
        text.fixedSize(horizontal: false, vertical: true)   // wrap to as many lines as the text needs
    }

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

/// A list row: optional leading text (a magnitude), title and subtitle, detail on the right, and either a
/// check box bound to a key or a tap that sends the row's id.
struct ListRow: View {
    @ObservedObject var model: ScreenModel
    let item: ScreenItem

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if !item.leading.isEmpty {
                Text(item.leading)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(item.accent.isEmpty ? Color.primary : Color(hex: item.accent))
                    .frame(minWidth: 36, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
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

/// A choice from a list: a pop-up menu for a few options, a separate list (with group headings) for many.
struct ChoiceRow: View {
    @ObservedObject var model: ScreenModel
    let item: ScreenItem

    private var currentLabel: String {
        item.options.first { $0.value == model.value(item.key) }?.label ?? model.value(item.key).string
    }

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

struct ChoiceList: View {
    @ObservedObject var model: ScreenModel
    let item: ScreenItem

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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A number: type it in, or use the stepper.
struct NumberRow: View {
    @ObservedObject var model: ScreenModel
    let item: ScreenItem

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

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

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
