import SwiftUI

/// The forum Filter sheet — involvement (Popular / I posted / I commented /
/// I'm mentioned), a search-as-you-type Countries multiselect, an On/Off toggle,
/// Clear, and named saved filters. Mirrors the web SPA's `openFilterPopup`.
/// Edits the shared `ForumFilterStore`; `onApply` re-pages the list / re-hides
/// the thread after every change.
struct FilterSheet: View {
    @Environment(ForumFilterStore.self) private var filter
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onApply: () -> Void

    @State private var query = ""
    @State private var saved: [SavedFilter] = []
    @State private var saveName = ""

    private let api = DcampAPI.shared
    private var views: [(ForumFilterStore.View, String, String)] {
        [(.popular, T("Popular"), "flame"),
         (.posted, T("I posted"), "square.and.pencil"),
         (.commented, T("I commented"), "bubble.left"),
         (.mentioned, T("I'm mentioned"), "at")]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    onOffRow
                    involvementSection
                    // Clear + saved filters sit above the long country checklist so
                    // they're reachable without scrolling past every country.
                    Button { filter.clear(); onApply(); dismiss() } label: {
                        Label(T("Clear filter"), systemImage: "xmark")
                    }
                    .foregroundStyle(Color.dcInkSoft)
                    if session.me != nil { savedSection }
                    countriesSection
                }
                .padding(18)
            }
            .background(Color.dcBg)
            .navigationTitle(T("Filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("Done")) { dismiss() } } }
        }
        .task { saved = await api.filtersList() }
    }

    private var onOffRow: some View {
        HStack {
            Text(T("Filter")).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.dcInk)
            Spacer()
            Toggle("", isOn: Binding(
                get: { filter.on },
                set: { _ in filter.toggleOn(); onApply() }
            ))
            .labelsHidden()
            .disabled(!filter.selected)
        }
    }

    private var involvementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Show")).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.dcMuted)
            FlowLayout(hSpacing: 8, vSpacing: 8) {
                ForEach(views, id: \.0) { v in
                    DCFilterPill(icon: v.2, title: v.1, active: filter.view == v.0) {
                        filter.setView(v.0); onApply()
                    }
                }
            }
        }
    }

    private var countriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(T("Countries")).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.dcMuted)
                Spacer()
                if !filter.countries.isEmpty {
                    Text(filter.countries.map { Countries.name($0) }.joined(separator: ", "))
                        .font(.system(size: 12)).foregroundStyle(Color.dcInkSoft).lineLimit(1)
                }
            }
            TextField(T("Search countries…"), text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            VStack(spacing: 0) {
                ForEach(visibleCodes, id: \.self) { code in
                    Button {
                        filter.toggleCountry(code); onApply()
                    } label: {
                        HStack {
                            Image(systemName: filter.hasCountry(code) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(filter.hasCountry(code) ? Color.dcAccent : Color.dcMuted)
                            Text(Countries.name(code)).foregroundStyle(Color.dcInk)
                            Spacer()
                        }
                        .padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.dcLine)
                }
            }
            .dcCard(padding: 12)
        }
    }

    /// Countries filtered by the search box; capped so the list stays light. Any
    /// already-checked country always shows (so it can be unchecked).
    private var visibleCodes: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            // selected first, then a slice of the rest
            let sel = Countries.sortedCodes.filter { filter.hasCountry($0) }
            let rest = Countries.sortedCodes.filter { !filter.hasCountry($0) }.prefix(60)
            return sel + rest
        }
        return Countries.sortedCodes.filter {
            filter.hasCountry($0) || Countries.name($0).lowercased().contains(q) || $0.lowercased() == q
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Saved filters")).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.dcMuted)
            ForEach(saved) { f in
                HStack {
                    Button {
                        filter.apply(spec: f.parsedSpec); onApply(); dismiss()
                    } label: {
                        Text(f.name).foregroundStyle(Color.dcAccentInk)
                    }
                    Spacer()
                    Button {
                        Task { await api.filterDelete(id: f.id); saved = await api.filtersList() }
                    } label: { Image(systemName: "trash").foregroundStyle(Color.dcMuted) }
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField(T("Name this filter…"), text: $saveName).textFieldStyle(.roundedBorder)
                Button(T("Save")) {
                    let nm = saveName.trimmingCharacters(in: .whitespaces)
                    guard !nm.isEmpty, filter.selected,
                          let data = try? JSONEncoder().encode(filter.spec),
                          let spec = String(data: data, encoding: .utf8) else { return }
                    Task {
                        await api.filterSave(name: nm, spec: spec)
                        saveName = ""
                        saved = await api.filtersList()
                    }
                }
                .buttonStyle(DCPrimaryButtonStyle())
                .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty || !filter.selected)
            }
        }
    }
}
