import Foundation

// MARK: - What Godot sends
//
// Godot describes a screen as JSON (a title, pages, and items such as toggles, choices, info rows and list
// rows) together with the current values. This file turns the JSON into plain Swift values;
// ScreenViews.swift draws them with SwiftUI. Preferences, About, the earthquake list and the other
// dialogs are all described this way, so one set of views serves them all.

/// A setting's value as it travels over JSON.
enum JSONValue: Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init?(any value: Any?) {
        if let n = value as? NSNumber {
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        } else if let s = value as? String {
            self = .string(s)
        } else {
            return nil
        }
    }

    /// The JSON text for this value (a bare scalar, which is what Godot's JSON parser expects).
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

    var string: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        }
    }
    var double: Double {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s) ?? 0
        case .bool(let b): return b ? 1 : 0
        }
    }
    var bool: Bool {
        if case .bool(let b) = self { return b }
        return double != 0
    }
}

struct ScreenOption: Identifiable {
    let id: String
    let label: String
    let value: JSONValue
    let group: String?
}

enum ItemKind: String {
    case section      // a heading for the items that follow
    case toggle       // on/off bound to a key
    case choice       // one of several options bound to a key
    case number       // a number with a stepper
    case color        // "#rrggbb"
    case text         // a text field bound to a key
    case action       // a button; tapping sends its id back
    case info         // a label and a value (read only)
    case paragraph    // a block of text
    case row          // a list row: accent, title, subtitle, detail; optional check box; tapping sends its id
}

struct ScreenItem: Identifiable {
    /// Stable across updates (position, kind, key and action id), so SwiftUI keeps scroll position, focus
    /// and open pages when Godot sends fresh content every second.
    let id: String
    let kind: ItemKind
    var key = ""
    var title = ""
    var options: [ScreenOption] = []
    var minimum = 0.0
    var maximum = 1.0
    var step = 1.0
    var suffix = ""
    var actionId = ""
    var detail = ""       // info: the value; row: text on the right
    var subtitle = ""     // row: second line
    var accent = ""       // row: "#rrggbb" for the leading text; also colors a destructive/prominent button
    var leading = ""      // row: short text before the title (a magnitude, say)
    var checkKey = ""     // row: key of a bool shown as a check box
    var style = ""        // paragraph: "title", "headline", "caption", "mono"; action: "destructive", "prominent"
    var selected = false  // row: highlighted as the current choice
    var dimmed = false    // row: drawn faded
    var confirm = ""      // action: ask this question (with the action as the answer) before sending it
}

struct ScreenPage: Identifiable {
    var id: String { title }
    let title: String
    let items: [ScreenItem]
}

struct ScreenSchema {
    var title = ""
    var pages: [ScreenPage] = []
    var doneTitle = "Done"
    var rootItems: [ScreenItem] = []   // shown under the list of pages (for example Reset All Settings)

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
            item.checkKey = d["check_key"] as? String ?? ""
            item.style = d["style"] as? String ?? ""
            item.confirm = d["confirm"] as? String ?? ""
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
