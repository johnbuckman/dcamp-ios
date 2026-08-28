import SwiftUI

/// The forum filter — involvement view + a set of countries — shared across every
/// board and the thread view, and persisted between launches, exactly like the
/// web SPA's `FORUM_FILTER` (localStorage "dcamp_forum_filter"). A selection means
/// "applied"; `on` lets the member suspend the selection without clearing it.
@Observable
final class ForumFilterStore {
    enum View: String, CaseIterable { case popular, posted, commented, mentioned }

    var view: View? = nil
    var countries: [String] = []        // ISO-2 codes
    var on: Bool = false

    private static let key = "dcamp_forum_filter"

    init() { load() }

    // MARK: derived state (mirrors forumFilterSelected / forumFilterActive)
    var selected: Bool { view != nil || !countries.isEmpty }
    var active: Bool { on && selected }

    /// Query params for the `messages` action (empty when the filter is off).
    var messageParams: [String: String] {
        guard active else { return [:] }
        var p: [String: String] = [:]
        if view == .popular { p["popular"] = "1" }
        else if let v = view { p["mine"] = v.rawValue }   // posted / commented / mentioned
        if !countries.isEmpty { p["countries"] = countries.joined(separator: ",") }
        return p
    }

    /// Short label for the chip: "Popular · France, Italy +2".
    var label: String {
        var bits: [String] = []
        if let v = view {
            let names: [View: String] = [.popular: "Popular", .posted: "I posted", .commented: "I commented", .mentioned: "I'm mentioned"]
            bits.append(names[v] ?? v.rawValue)
        }
        if !countries.isEmpty {
            let head = countries.prefix(3).map { Countries.name($0) }.joined(separator: ", ")
            bits.append(head + (countries.count > 3 ? " +\(countries.count - 3)" : ""))
        }
        return bits.joined(separator: " · ")
    }

    // MARK: mutation
    func setView(_ v: View) { view = (view == v) ? nil : v; onChanged() }
    func toggleCountry(_ code: String) {
        if let i = countries.firstIndex(of: code) { countries.remove(at: i) } else { countries.append(code) }
        onChanged()
    }
    func hasCountry(_ code: String) -> Bool { countries.contains(code) }

    /// Turn the current selection on/off without clearing it.
    func toggleOn() { guard selected else { return }; on.toggle(); save() }

    func clear() { view = nil; countries = []; on = false; save() }

    /// Apply a saved spec (from a named saved filter).
    func apply(spec: SavedFilterSpec) {
        view = spec.view.flatMap { View(rawValue: $0) }
        countries = spec.countries
        on = selected
        save()
    }

    /// The spec to persist as a named saved filter.
    var spec: SavedFilterSpec { SavedFilterSpec(view: view?.rawValue, countries: countries) }

    /// Any edit that leaves a selection turns the filter on (a selection = applied).
    private func onChanged() { on = selected; save() }

    // MARK: persistence
    private func save() {
        let dict: [String: Any] = ["view": view?.rawValue ?? "", "countries": countries, "on": on]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let v = d["view"] as? String, !v.isEmpty { view = View(rawValue: v) }
        countries = (d["countries"] as? [String]) ?? []
        on = ((d["on"] as? Bool) ?? false) && selected
    }
}

/// The JSON spec stored in a named saved filter (`{view, countries}`).
struct SavedFilterSpec: Codable {
    var view: String?
    var countries: [String] = []
}

/// A member's named saved filter (server `filters_list`).
struct SavedFilter: Codable, Identifiable {
    var id: Int
    var name: String
    var spec: String            // JSON string of SavedFilterSpec

    var parsedSpec: SavedFilterSpec {
        guard let data = spec.data(using: .utf8),
              let s = try? JSONDecoder().decode(SavedFilterSpec.self, from: data) else { return SavedFilterSpec() }
        return s
    }
}
