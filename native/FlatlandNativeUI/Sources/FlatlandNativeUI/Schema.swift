import Foundation

// MARK: - What Godot sends
//
// Godot describes a screen as JSON (a title, pages, and items such as toggles, choices, info rows and list
// rows) together with the current values. This file turns the JSON into plain Swift values;
// ScreenViews.swift draws them with SwiftUI. Preferences, About, the earthquake list and the other
// dialogs are all described this way, so one set of views serves them all.

/// A setting's value as it travels over JSON between Godot and the native screen: text, a number or a true/false
/// value. It converts itself to the type a control needs (`string`, `double`, `bool`) and to JSON text for sending
/// back to Godot (`jsonText`).
enum JSONValue: Hashable {
    /// Text.
    case string(String)
    /// A number (JSON has one number type; whole numbers are shown without a decimal point by `string`).
    case number(Double)
    /// A true/false value.
    case bool(Bool)

    /// Makes a value from what JSONSerialization produced.
    ///
    /// - Parameter value: an NSNumber (a bool or a number) or a String.
    /// - Returns: nil (the initializer fails) for anything else.
    init?(any value: Any?) {
        if let n = value as? NSNumber {
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        } else if let s = value as? String {
            self = .string(s)
        } else {
            return nil
        }
    }

    /// The JSON text for this value: a bare scalar, which is what Godot's JSON parser expects when it reads a value
    /// back ("true", "3.5" or "\"text\"").
    var jsonText: String {
        let object: Any
        switch self {
        case .string(let s): object = s
        case .number(let n): object = n
        case .bool(let b): object = b
        }
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    /// The value as text: a number with no fraction is written without a decimal point, a bool as "true" or "false".
    var string: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        }
    }
    /// The value as a number: text is parsed (0 if it is not a number) and a bool is 1 or 0.
    var double: Double {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s) ?? 0
        case .bool(let b): return b ? 1 : 0
        }
    }
    /// The value as a bool: a bool as itself, anything else true when it is not zero.
    var bool: Bool {
        if case .bool(let b) = self { return b }
        return double != 0
    }
}

/// One choice of a "choice" item (a drop-down or list): what the user sees and what is stored.
struct ScreenOption: Identifiable {
    /// Position of the option in its list, as text; makes the option identifiable for SwiftUI.
    let id: String
    /// The text shown to the user.
    let label: String
    /// The value stored (and sent to Godot) when it is chosen.
    let value: JSONValue
    /// The heading this option is listed under in a long list (the map groups), or nil.
    let group: String?
}

/// The kinds of item a screen can contain; the raw value is the "type" field of the JSON. The same items are
/// described by the Godot dialogs and drawn by ScreenViews.swift.
enum ItemKind: String {
    /// A heading for the items that follow.
    case section
    /// An on/off switch bound to a key.
    case toggle
    /// One of several options, bound to a key.
    case choice
    /// A number with a stepper.
    case number
    /// A color, stored as "#rrggbb".
    case color
    /// A text field bound to a key.
    case text
    /// A button; tapping it sends its id back to Godot.
    case action
    /// A label and a value (read only).
    case info
    /// A block of text.
    case paragraph
    /// A list row: accent, title, subtitle and detail, with an optional check box; tapping it sends its id.
    case row
    /// A picture from the file at `path`, scaled to fit the width.
    case image
    /// A row that opens a page of text inside the screen (with a Back button): `title` is the row, `pageTitle` the
    /// page's title and `detail` the text.
    case link
}

/// One item on a screen, described by the JSON Godot sent. Only the fields that apply to its `kind` are used (see
/// each field).
struct ScreenItem: Identifiable {
    /// Stable across updates (position, kind, key and action id; for rows, the action id), so SwiftUI keeps scroll
    /// position, focus and open pages when Godot sends fresh content every second.
    let id: String
    /// What kind of item this is.
    let kind: ItemKind
    /// The key of the value this item edits (toggle, choice, number, color, text).
    var key = ""
    /// The item's main text: the label, button title, heading or paragraph text.
    var title = ""
    /// The choices of a "choice" item.
    var options: [ScreenOption] = []
    /// Smallest value of a "number" item.
    var minimum = 0.0
    /// Largest value of a "number" item.
    var maximum = 1.0
    /// Step of a "number" item's stepper.
    var step = 1.0
    /// Text after the number of a "number" item, such as " s".
    var suffix = ""
    /// The id sent to Godot when an action or row is tapped.
    var actionId = ""
    /// Info: the value shown. Row: the text on the right. Link: the text of the page it opens.
    var detail = ""
    /// Row: the second line.
    var subtitle = ""
    /// Row: "#rrggbb" for the leading text. Also colors a destructive or prominent button.
    var accent = ""
    /// Row: short text before the title (a magnitude, say).
    var leading = ""
    /// Row: short text shown in a small red capsule after the title (such as "NEW").
    var badge = ""
    /// Row: "#rrggbb" for a filled dot drawn before the leading text. When set, the leading text is drawn in the normal
    /// text color instead of [accent].
    var dot = ""
    /// Row: the key of a bool shown as a check box.
    var checkKey = ""
    /// Paragraph: "title", "headline", "caption" or "mono". Action: "destructive" or "prominent".
    var style = ""
    /// Row: highlighted as the current choice.
    var selected = false
    /// Row: drawn faded.
    var dimmed = false
    /// Action: if not empty, this question is asked (with the action as the answer) before the id is sent.
    var confirm = ""
    /// Image: the picture's file path.
    var path = ""
    /// Link: the title of the page it opens.
    var pageTitle = ""
}

/// One page of a screen: a title (shown in the list of pages) and its items.
struct ScreenPage: Identifiable {
    /// The page's identity: its title.
    var id: String { title }
    /// The page's title.
    let title: String
    /// The page's items, in order.
    let items: [ScreenItem]
}

/// The description of a whole screen (a title, pages, and the items shown under the list of pages), turned from the
/// JSON Godot sends into plain Swift values. ScreenViews.swift draws it.
struct ScreenSchema {
    /// The screen's title.
    var title = ""
    /// The pages. A screen with one page shows it directly; with several it shows a list of them.
    var pages: [ScreenPage] = []
    /// The title of the Done button (default "Done").
    var doneTitle = "Done"
    /// Items shown under the list of pages (for example Reset All Settings).
    var rootItems: [ScreenItem] = []

    /// Reads a screen description.
    ///
    /// - Parameter json: the JSON text from Godot ("title", "done_title", "pages" and "root_items"). If it cannot be
    /// read, the schema is left empty.
    init(json: String) {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        title = root["title"] as? String ?? title
        doneTitle = root["done_title"] as? String ?? doneTitle
        for p in root["pages"] as? [[String: Any]] ?? [] {
            pages.append(ScreenPage(title: p["title"] as? String ?? "", items: Self.items(p["items"] as? [[String: Any]] ?? [])))
        }
        rootItems = Self.items(root["root_items"] as? [[String: Any]] ?? [])
    }

    /// Reads a list of item descriptions. Items with an unknown "type" are skipped. Rows are identified by their
    /// action id (they come and go as data changes); everything else by position, kind, key and action id.
    ///
    /// - Parameter list: the decoded JSON items.
    /// - Returns: the items.
    private static func items(_ list: [[String: Any]]) -> [ScreenItem] {
        var items: [ScreenItem] = []
        for (index, d) in list.enumerated() {
            guard let kind = ItemKind(rawValue: d["type"] as? String ?? "") else { continue }
            let key = d["key"] as? String ?? ""
            let actionId = d["id"] as? String ?? ""
            // Rows are identified by their action id (they come and go as data changes); everything else by position.
            let stable = kind == .row && !actionId.isEmpty ? "row-\(actionId)" : "\(index)-\(kind.rawValue)-\(key)-\(actionId)"
            var item = ScreenItem(id: stable, kind: kind)
            item.key = key
            item.title = d["title"] as? String ?? ""
            item.minimum = (d["min"] as? NSNumber)?.doubleValue ?? 0
            item.maximum = (d["max"] as? NSNumber)?.doubleValue ?? 1
            item.step = (d["step"] as? NSNumber)?.doubleValue ?? 1
            item.suffix = d["suffix"] as? String ?? ""
            item.actionId = actionId
            item.detail = d["detail"] as? String ?? ""
            item.subtitle = d["subtitle"] as? String ?? ""
            item.accent = d["accent"] as? String ?? ""
            item.leading = d["leading"] as? String ?? ""
            item.dot = d["dot"] as? String ?? ""
            item.badge = d["badge"] as? String ?? ""
            item.checkKey = d["check_key"] as? String ?? ""
            item.style = d["style"] as? String ?? ""
            item.confirm = d["confirm"] as? String ?? ""
            item.path = d["path"] as? String ?? ""
            item.pageTitle = d["page_title"] as? String ?? ""
            item.selected = d["selected"] as? Bool ?? false
            item.dimmed = d["dimmed"] as? Bool ?? false
            for (n, o) in (d["options"] as? [[String: Any]] ?? []).enumerated() {
                if let v = JSONValue(any: o["value"]) {
                    item.options.append(ScreenOption(id: "\(n)", label: o["label"] as? String ?? v.string, value: v, group: o["group"] as? String))
                }
            }
            items.append(item)
        }
        return items
    }

    /// Reads the current values of a screen.
    ///
    /// - Parameter json: a JSON object text mapping keys to values.
    /// - Returns: the values by key (entries that are not text, number or bool are dropped); empty if the JSON cannot
    /// be read.
    static func values(json: String) -> [String: JSONValue] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: JSONValue] = [:]
        for (k, v) in root {
            if let value = JSONValue(any: v) { out[k] = value }
        }
        return out
    }
}
