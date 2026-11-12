import AppKit
import EventKit
import MapKit
import SwiftUI

@MainActor @Observable final class CalendarAgenda {
    struct CalendarChoice: Identifiable, Equatable {
        let id: String
        let title: String
        let account: String
        let writable: Bool
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let title: String
        let calendar: String
        let calendarID: String
        let writable: Bool
        let start: Date
        let end: Date
        let allDay: Bool
        let location: String?
        let coordinates: CLLocation?
        let notes: String?
    }

    enum Display: String, CaseIterable {
        case list, month
        var label: String { self == .list ? "Lista impegni" : "Calendario mensile" }
    }

    private static let displayKey = "calendarAgenda.display"
    private static let selectionKey = "calendarAgenda.selectedCalendars"
    @ObservationIgnored private lazy var store = EKEventStore()
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var nextRefresh = Date.distantPast
    @ObservationIgnored private var eventEditor: NSWindow?
    private(set) var selected: Set<String>
    private(set) var calendars: [CalendarChoice] = []
    private(set) var entries: [Entry] = []
    private(set) var markedDays: Set<Date> = []
    var hoveredDays: [String: Date] = [:]
    private(set) var daySelections: [String: DaySelection] = [:]
    private var monthEntries: [Date: [Entry]] = [:]
    private var browsedMonths: [String: Date] = [:]

    struct DaySelection {
        let date: Date
        var page = 0
    }
    private(set) var display: Display
    private(set) var authorization = EKAuthorizationStatus.notDetermined
    private(set) var requesting = false
    private(set) var requestFailed = false

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        display = defaults?.string(forKey: Self.displayKey).flatMap(Display.init(rawValue:)) ?? .list
        selected = Set(defaults?.stringArray(forKey: Self.selectionKey) ?? [])
    }

    func setDisplay(_ value: Display) {
        guard value != display else { return }
        display = value
        daySelections.removeAll()
        hoveredDays.removeAll()
        browsedMonths.removeAll()
        defaults?.set(value.rawValue, forKey: Self.displayKey)
        refresh(force: true)
    }

    func openDay(_ date: Date, displayID: String, screen: NSScreen?) {
        guard markedDays.contains(date) else {
            openEventEditor(on: date, screen: screen)
            return
        }
        daySelections[displayID] = DaySelection(date: date)
    }

    func openEventEditor(on date: Date? = nil, editing entry: Entry? = nil, duplicating copy: Entry? = nil,
                         confirmDelete: Bool = false, screen: NSScreen?) {
        let window: NSWindow
        if let eventEditor, eventEditor.isVisible {
            window = eventEditor
        } else {
            refresh(force: true)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 550),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered,
                              defer: false, screen: screen)
            window.isReleasedWhenClosed = false
            window.title = L(entry == nil ? "Nuovo evento" : "Modifica evento")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            let editor = CalendarEventEditor(agenda: self, date: date, entry: entry, copy: copy, confirmDelete: confirmDelete) { [weak window] in
                window?.close()
            }
            let hosting = NSHostingView(rootView: LocalizedRoot(content: editor))
            hosting.safeAreaRegions = []
            window.contentView = hosting
            eventEditor = window
        }
        if let screen {
            window.setFrame(Self.centeredFrame(window.frame.size, in: screen.visibleFrame), display: false)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func centeredFrame(_ size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        return CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.midY - height / 2, width: width, height: height)
    }

    static func convertedEventRange(start: Date, end: Date, allDay: Bool, calendar: Calendar) -> (start: Date, end: Date) {
        if allDay {
            return (calendar.startOfDay(for: start), calendar.startOfDay(for: max(start, end.addingTimeInterval(-1))))
        }
        let first = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start
        let last = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: end) ?? end
        return (first, max(first.addingTimeInterval(3600), last))
    }

    func saveEvent(title: String, start: Date, end: Date, allDay: Bool, location: String, mappedLocation: EKStructuredLocation?, notes: String,
                   calendarID: String, editing entry: Entry?) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, start < end else { throw SettingsError.invalid("Inserisci un titolo e un orario valido.") }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw SettingsError.invalid("Consenti l’accesso ai calendari da Impostazioni di Sorayura.")
        }
        guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications,
              calendar.allowedEntityTypes.contains(.event) else {
            throw SettingsError.invalid("Scegli un calendario modificabile.")
        }
        let event = try entry.map(eventToEdit) ?? EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = end
        if let mappedLocation {
            event.structuredLocation = mappedLocation
        } else if (event.location ?? "") != location {
            event.structuredLocation = nil
            event.location = location.isEmpty ? nil : location
        }
        event.notes = notes.isEmpty ? nil : notes
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        refresh(force: true)
    }

    func eventActions(for entry: Entry, screen: NSScreen?) -> [(String, () -> Void)] {
        var actions: [(String, () -> Void)] = []
        if entry.writable {
            actions.append(("Modifica evento…", { self.openEventEditor(editing: entry, screen: screen) }))
        }
        actions.append(("Duplica evento…", { self.openEventEditor(duplicating: entry, screen: screen) }))
        actions.append(("Copia titolo", {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.title, forType: .string)
        }))
        if let coordinates = entry.coordinates {
            actions.append(("Apri in Mappe", { Self.openMaps(at: coordinates, name: entry.location) }))
        }
        if entry.writable {
            actions.append(("Elimina evento…", { self.openEventEditor(editing: entry, confirmDelete: true, screen: screen) }))
        }
        return actions
    }

    static func openMaps(at location: CLLocation, name: String?) {
        let item: MKMapItem
        if #available(macOS 26, *) {
            item = MKMapItem(location: location, address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        }
        item.name = name
        item.openInMaps(launchOptions: nil)
    }

    func deleteEvent(_ entry: Entry) throws {
        try store.remove(eventToEdit(entry), span: .thisEvent, commit: true)
        refresh(force: true)
    }

    private func eventToEdit(_ entry: Entry) throws -> EKEvent {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.calendar(withIdentifier: entry.calendarID), calendar.allowsContentModifications else {
            throw SettingsError.invalid("Scegli un calendario modificabile.")
        }
        let start = entry.start
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-1),
                                                 end: start.addingTimeInterval(1), calendars: [calendar])
        // Identifier lookups return the first occurrence of a recurring event.
        guard let event = store.events(matching: predicate).first(where: {
            $0.status != .canceled && Self.entry($0).id == entry.id
        }) else { throw SettingsError.invalid("L’evento è cambiato o non è più disponibile.") }
        return event
    }

    func closeDay(displayID: String) {
        daySelections.removeValue(forKey: displayID)
    }

    func setPage(_ page: Int, displayID: String) {
        daySelections[displayID]?.page = page
    }

    func visibleMonth(displayID: String, now: Date = .now) -> CalendarMonth? {
        CalendarMonth(date: browsedMonths[displayID] ?? now, calendar: .current)
    }

    func moveMonth(by offset: Int, displayID: String, now: Date = .now) {
        let calendar = Calendar.current
        guard let current = calendar.dateInterval(of: .month, for: now)?.start,
              let visible = visibleMonth(displayID: displayID, now: now)?.interval.start,
              let next = calendar.date(byAdding: .month, value: offset, to: offset == 0 ? current : visible) else { return }
        browsedMonths[displayID] = next == current ? nil : next
        closeDay(displayID: displayID)
        hoveredDays[displayID] = nil
        refresh(force: true)
    }

    func events(on date: Date) -> [Entry] {
        guard let month = CalendarMonth(date: date, calendar: .current) else { return [] }
        return (monthEntries[month.interval.start] ?? []).filter { month.overlaps(date, start: $0.start, end: $0.end) }
    }

    func requestAccess() async {
        guard defaults != nil, !requesting else { return }
        requesting = true
        requestFailed = false
        defer { requesting = false; refresh(force: true) }
        do { _ = try await store.requestFullAccessToEvents() }
        catch { requestFailed = true }
    }

    func select(_ id: String, enabled: Bool) {
        guard let defaults, calendars.contains(where: { $0.id == id }) else { return }
        if enabled { selected.insert(id) } else { selected.remove(id) }
        defaults.set(selected.sorted(), forKey: Self.selectionKey)
        refresh(force: true)
    }

    func refresh(force: Bool = false) {
        guard defaults != nil else { return }
        let now = Date()
        guard force || (!selected.isEmpty && now >= nextRefresh) else { return }
        nextRefresh = now.addingTimeInterval(60)
        let status = EKEventStore.authorizationStatus(for: .event)
        if authorization != status {
            if status == .fullAccess { store.reset() }
            authorization = status
        }
        guard status == .fullAccess else {
            if !calendars.isEmpty { calendars = [] }
            if !entries.isEmpty { entries = [] }
            if !markedDays.isEmpty { markedDays = [] }
            if !monthEntries.isEmpty { monthEntries = [:] }
            if !daySelections.isEmpty { daySelections.removeAll() }
            return
        }

        let available = store.calendars(for: .event)
        let choices = available.map {
            CalendarChoice(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title,
                           writable: $0.allowsContentModifications)
        }.sorted {
            ($0.account + "\n" + $0.title).localizedStandardCompare($1.account + "\n" + $1.title) == .orderedAscending
        }
        if calendars != choices { calendars = choices }
        let active = available.filter { selected.contains($0.calendarIdentifier) }
        guard !active.isEmpty, let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else {
            if !entries.isEmpty { entries = [] }
            if !markedDays.isEmpty { markedDays = [] }
            if !monthEntries.isEmpty { monthEntries = [:] }
            if !daySelections.isEmpty { daySelections.removeAll() }
            return
        }
        if display == .month {
            var details: [Date: [Entry]] = [:]
            var marks: Set<Date> = []
            let calendar = Calendar.current
            let starts = Set((Array(browsedMonths.values) + [now]).compactMap {
                calendar.dateInterval(of: .month, for: $0)?.start
            })
            for start in starts {
                guard let month = CalendarMonth(date: start, calendar: calendar) else { continue }
                let predicate = store.predicateForEvents(withStart: start, end: month.interval.end, calendars: active)
                let events = store.events(matching: predicate).filter { $0.status != .canceled }
                    .sorted { $0.compareStartDate(with: $1) == .orderedAscending }
                details[start] = events.map(Self.entry)
                for case let day? in month.days where events.contains(where: {
                    month.overlaps(day, start: $0.startDate, end: $0.endDate)
                }) {
                    marks.insert(day)
                }
            }
            if monthEntries != details { monthEntries = details }
            if markedDays != marks { markedDays = marks }
            let visibleSelections = daySelections.filter { displayID, selection in
                guard let interval = visibleMonth(displayID: displayID, now: now)?.interval else { return false }
                return selection.date >= interval.start && selection.date < interval.end
            }
            if visibleSelections.count != daySelections.count { daySelections = visibleSelections }
            if !entries.isEmpty { entries = [] }
            return
        }
        if !markedDays.isEmpty { markedDays = [] }
        if !monthEntries.isEmpty { monthEntries = [:] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: active)
        let upcoming = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .sorted { $0.compareStartDate(with: $1) == .orderedAscending }
            .prefix(24)
            .map(Self.entry)
        if entries != upcoming { entries = upcoming }
    }

    private static func entry(_ event: EKEvent) -> Entry {
        Entry(id: "\(event.calendar.calendarIdentifier):\(event.calendarItemIdentifier):\(event.startDate.timeIntervalSinceReferenceDate)",
              title: event.title?.isEmpty == false ? event.title : L("Evento senza titolo"),
              calendar: event.calendar.title, calendarID: event.calendar.calendarIdentifier,
              writable: event.calendar.allowsContentModifications,
              start: event.startDate, end: event.endDate, allDay: event.isAllDay,
              location: event.location, coordinates: event.structuredLocation?.geoLocation, notes: event.notes)
    }

    var statusMessage: String {
        if authorization != .fullAccess { return "Consenti l’accesso ai calendari da Impostazioni di Sorayura." }
        if selected.isDisjoint(with: calendars.map(\.id)) { return "Scegli i calendari da mostrare." }
        return "Nessun impegno nei prossimi 7 giorni."
    }
}

struct CalendarSettings: View {
    let agenda: CalendarAgenda

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("Vista calendario"), selection: Binding(get: { agenda.display }, set: { agenda.setDisplay($0) })) {
                ForEach(CalendarAgenda.Display.allCases, id: \.self) { display in
                    Text(L(display.label)).tag(display)
                }
            }.pickerStyle(.segmented)
            Text(L("Collega Google in Calendario → Aggiungi account, poi scegli qui quali calendari mostrare."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("Apri Calendario")) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                if agenda.authorization == .notDetermined || agenda.authorization == .writeOnly {
                    Button(L("Consenti accesso ai calendari…")) { Task { await agenda.requestAccess() } }
                        .disabled(agenda.requesting)
                } else if agenda.authorization != .fullAccess {
                    Button(L("Apri impostazioni privacy…")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Button(L("Aggiorna calendari")) { agenda.refresh(force: true) }
            }
            if agenda.authorization == .fullAccess {
                ForEach(agenda.calendars) { calendar in
                    Toggle(isOn: Binding(get: { agenda.selected.contains(calendar.id) },
                                         set: { agenda.select(calendar.id, enabled: $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.title)
                            Text(calendar.account).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if agenda.calendars.isEmpty { Text(L("Nessun calendario disponibile.")).foregroundStyle(.secondary) }
            } else {
                Text(L(agenda.requestFailed ? "Impossibile richiedere l’accesso ai calendari." : agenda.statusMessage))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { agenda.refresh(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            agenda.refresh(force: true)
        }
    }
}

@MainActor @Observable
final class CalendarPlaceSearch: NSObject, @preconcurrency MKLocalSearchCompleterDelegate, @preconcurrency CLLocationManagerDelegate {
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var locationManager: CLLocationManager?
    @ObservationIgnored private var locationTimeout: Task<Void, Never>?
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private(set) var isLocating = false
    private(set) var isNearby = false
    private(set) var locationUnavailable = false
    private(set) var showLocationSettings = false
    private var query = ""
    private var requestedLocation = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ text: String) {
        let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next != query else { return }
        query = next
        suggestions = []
        if query.count >= 3 { completer.queryFragment = query }
        else {
            completer.cancel()
            completer.queryFragment = ""
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard query.count >= 3, completer.queryFragment == query else { return }
        suggestions = Array(completer.results.prefix(12))
    }

    func resolve(_ suggestion: MKLocalSearchCompletion) async throws -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: suggestion)
        if isNearby { request.region = completer.region }
        return try await MKLocalSearch(request: request).start().mapItems.first
    }

    func useNearby() {
        guard !isLocating, !isNearby else { return }
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        isLocating = true
        locationUnavailable = false
        showLocationSettings = false
        requestedLocation = false
        locationManager = manager
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            startLocationTimeout(after: .seconds(30))
            manager.requestWhenInUseAuthorization()
        } else {
            locationManagerDidChangeAuthorization(manager)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === locationManager else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestedLocation else { return }
            requestedLocation = true
            startLocationTimeout(after: .seconds(12))
            manager.requestLocation()
        case .denied, .restricted:
            showLocationSettings = true
            finishLocation(nil)
        case .notDetermined: break
        @unknown default: finishLocation(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if manager === locationManager { finishLocation(locations.last) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === locationManager else { return }
        showLocationSettings = (error as? CLError)?.code == .denied
        finishLocation(nil)
    }

    private func startLocationTimeout(after delay: Duration) {
        locationTimeout?.cancel()
        locationTimeout = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            showLocationSettings = locationManager?.authorizationStatus == .notDetermined
            finishLocation(nil)
        }
    }

    private func finishLocation(_ location: CLLocation?) {
        stopLocation()
        guard let location, location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate) else {
            locationUnavailable = true
            return
        }
        isNearby = true
        completer.region = Self.nearbyRegion(around: location.coordinate)
        if query.count >= 3 {
            suggestions = []
            completer.cancel()
            completer.queryFragment = ""
            completer.queryFragment = query
        }
    }

    static func nearbyRegion(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let approximate = CLLocationCoordinate2D(latitude: (coordinate.latitude * 100).rounded() / 100,
                                                 longitude: (coordinate.longitude * 100).rounded() / 100)
        return MKCoordinateRegion(center: approximate, latitudinalMeters: 24_000, longitudinalMeters: 24_000)
    }

    func stop() {
        update("")
        stopLocation()
    }

    private func stopLocation() {
        locationTimeout?.cancel()
        locationTimeout = nil
        locationManager?.delegate = nil
        locationManager?.stopUpdatingLocation()
        locationManager = nil
        isLocating = false
    }
}

struct CalendarEventEditor: View {
    private enum FocusedControl { case title, delete }

    private struct LocationFieldBounds: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil

        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

    unowned let agenda: CalendarAgenda
    let entry: CalendarAgenda.Entry?
    let close: () -> Void
    let confirmDeleteOnOpen: Bool
    @State private var title = ""
    @State private var calendarID = ""
    @State private var hasDate: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var location: String
    @State private var mappedLocation: EKStructuredLocation?
    @State private var placeSearch = CalendarPlaceSearch()
    @State private var resolvingPlace: MKLocalSearchCompletion?
    @State private var placeResolutionFailed = false
    private let originalLocation: String?
    private let originalCoordinates: CLLocation?
    @State private var notes: String
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var deleteHovered = false
    @FocusState private var focusedControl: FocusedControl?

    init(agenda: CalendarAgenda, date: Date?, entry: CalendarAgenda.Entry?, copy: CalendarAgenda.Entry?,
         confirmDelete: Bool, close: @escaping () -> Void) {
        self.agenda = agenda
        self.entry = entry
        self.close = close
        self.confirmDeleteOnOpen = confirmDelete
        let source = entry ?? copy
        let start = source?.start ?? date.flatMap { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: $0) } ?? .now
        let end = source?.end ?? start.addingTimeInterval(3600)
        _title = State(initialValue: source?.title ?? "")
        _location = State(initialValue: source?.location ?? "")
        originalLocation = source?.location
        originalCoordinates = source?.coordinates
        if let copy, let coordinates = copy.coordinates {
            let place = EKStructuredLocation(title: copy.location ?? "")
            place.geoLocation = coordinates
            _mappedLocation = State(initialValue: place)
        }
        _notes = State(initialValue: source?.notes ?? "")
        _allDay = State(initialValue: source?.allDay ?? false)
        _start = State(initialValue: start)
        _end = State(initialValue: source?.allDay == true ? Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end : end)
        _hasDate = State(initialValue: date != nil || source != nil)
        let preferred = agenda.calendars.first { $0.writable && agenda.selected.contains($0.id) }
        _calendarID = State(initialValue: source?.writable == true ? (source?.calendarID ?? "") : (date != nil || copy != nil ? preferred?.id ?? "" : ""))
    }

    private var savedEnd: Date {
        allDay ? Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end : end
    }

    var body: some View {
        let writable = agenda.calendars.filter(\.writable)
        VStack(alignment: .leading, spacing: 16) {
            Label(L(entry == nil ? "Nuovo evento" : "Modifica evento"), systemImage: entry == nil ? "calendar.badge.plus" : "calendar")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(L("Titolo evento"), text: $title)
                    .textFieldStyle(.plain)
                    .focused($focusedControl, equals: .title)
                    .font(.title3.weight(.medium))
                    .padding(12)
                    .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 10) {
                        if hasDate {
                            Toggle(L("Tutto il giorno"), isOn: Binding(get: { allDay }, set: setAllDay))
                                .toggleStyle(.checkbox)
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                dateRow("Inizio evento", selection: Binding(get: { start }, set: moveStart), showDuration: true)
                                dateRow("Fine evento", selection: $end)
                            }
                        } else {
                            Button { hasDate = true } label: {
                                Label(L("Imposta data e ora"), systemImage: "clock")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor.opacity(0.7)).frame(width: 3).padding(.vertical, 10)
                    }
                    locationField
                    Picker(L("Calendario"), selection: $calendarID) {
                        Text(L("Scegli un calendario modificabile.")).tag("")
                        ForEach(writable) { calendar in
                            Text("\(calendar.title) — \(calendar.account)").tag(calendar.id)
                        }
                    }
                    .padding(12)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    TextField(L("Note evento"), text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .overlayPreferenceValue(LocationFieldBounds.self) { anchor in
                if let anchor, !placeSearch.suggestions.isEmpty, resolvingPlace == nil {
                    GeometryReader { geometry in
                        let field = geometry[anchor]
                        if let panel = Self.suggestionsFrame(below: field, viewportHeight: geometry.size.height) {
                            locationSuggestions
                                .frame(width: panel.width, height: panel.height)
                                .offset(x: panel.minX, y: panel.minY)
                        }
                    }
                }
            }
            if agenda.authorization != .fullAccess {
                Text(L("Consenti l’accesso ai calendari da Impostazioni di Sorayura."))
                    .foregroundStyle(.secondary)
            } else if writable.isEmpty {
                Text(L("Scegli un calendario modificabile.")).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if entry != nil {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(L("Elimina evento"), systemImage: "trash")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(focusedControl == .delete ? 0.26 : (deleteHovered ? 0.18 : 0)),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focusedControl, equals: .delete)
                    .focusEffectDisabled()
                    .foregroundStyle(.red)
                    .onHover { deleteHovered = $0 }
                }
                Spacer()
                Button(L("Annulla"), action: close).buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                Button(L("Salva")) {
                    do {
                        try agenda.saveEvent(title: title, start: start, end: savedEnd, allDay: allDay,
                                             location: location, mappedLocation: mappedLocation, notes: notes,
                                             calendarID: calendarID, editing: entry)
                        close()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(resolvingPlace != nil || !hasDate || start >= savedEnd || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          !writable.contains(where: { $0.id == calendarID }))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 22)
        .defaultFocus($focusedControl, .title)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(colors: [Color.accentColor.opacity(0.20), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .alert(L("Eliminare l’evento?"), isPresented: $confirmDelete) {
            Button(L("Annulla"), role: .cancel) {}
            Button(L("Elimina evento"), role: .destructive) {
                guard let entry else { return }
                do { try agenda.deleteEvent(entry); close() }
                catch { self.error = error.localizedDescription }
            }
        } message: {
            if let entry { Text(entry.title) }
        }
        .task { if confirmDeleteOnOpen { confirmDelete = true } }
        .task(id: resolvingPlace) {
            if let resolvingPlace { await selectPlace(resolvingPlace) }
        }
        .onDisappear { placeSearch.stop() }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(L("Luogo evento"), text: Binding(get: { location }, set: { value in
                    location = value
                    mappedLocation = nil
                    resolvingPlace = nil
                    placeResolutionFailed = false
                    placeSearch.update(value)
                }))
                .textFieldStyle(.plain)
                if placeSearch.isLocating || resolvingPlace != nil {
                    ProgressView().controlSize(.small)
                }
                if let coordinates = mappedLocation?.geoLocation ?? (location == originalLocation ? originalCoordinates : nil) {
                    Button {
                        CalendarAgenda.openMaps(at: coordinates, name: location)
                    } label: { Image(systemName: "map") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L("Apri in Mappe"))
                    .help(L("Apri in Mappe"))
                }
                Button {
                    placeSearch.useNearby()
                } label: {
                    Image(systemName: placeSearch.isNearby ? "location.fill" : "location")
                }
                .buttonStyle(.borderless)
                .disabled(placeSearch.isLocating || placeSearch.isNearby)
                .accessibilityLabel(L("Vicino a me"))
                .help(L("Vicino a me"))
            }
            .padding(12)
            if placeSearch.locationUnavailable || placeResolutionFailed {
                Text(L(placeResolutionFailed ? "Impossibile trovare il luogo selezionato." : "Posizione non disponibile."))
                    .font(.caption).foregroundStyle(.secondary).padding([.horizontal, .bottom], 12)
            }
            if placeSearch.showLocationSettings {
                Button(L("Apri impostazioni privacy…")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding([.horizontal, .bottom], 12)
            }
        }
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .anchorPreference(key: LocationFieldBounds.self, value: .bounds) { $0 }
    }

    static func suggestionsFrame(below field: CGRect, viewportHeight: CGFloat) -> CGRect? {
        guard field.maxY > 0, field.minY < viewportHeight else { return nil }
        let gap: CGFloat = 6
        let below = viewportHeight - field.maxY - gap
        let above = field.minY - gap
        let opensBelow = below >= 150 || below >= above
        let height = min(210, opensBelow ? below : above)
        guard height >= 44 else { return nil }
        return CGRect(x: field.minX, y: opensBelow ? field.maxY + gap : above - height,
                      width: field.width, height: height)
    }

    private var locationSuggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(placeSearch.suggestions, id: \.self) { suggestion in
                    Button {
                        placeResolutionFailed = false
                        resolvingPlace = suggestion
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).fontWeight(.medium)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .background(.thickMaterial)
        .clipShape(.rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.15)).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    private static func address(of item: MKMapItem) -> String? {
        if #available(macOS 26, *) { return item.address?.fullAddress }
        return item.placemark.title
    }

    private func selectPlace(_ suggestion: MKLocalSearchCompletion) async {
        let item = try? await placeSearch.resolve(suggestion)
        guard !Task.isCancelled, resolvingPlace === suggestion else { return }
        resolvingPlace = nil
        guard let item else {
            placeResolutionFailed = true
            return
        }
        let place = EKStructuredLocation(mapItem: item)
        let name = item.name ?? suggestion.title
        let address = Self.address(of: item)
        location = [name, address == name ? nil : address].compactMap { $0 }.joined(separator: ", ")
        place.title = location
        mappedLocation = place
        placeSearch.update("")
    }

    private var durationMenu: some View {
        Menu {
            ForEach([30, 60, 90, 120, 150, 180], id: \.self) { minutes in
                let proposed = start.addingTimeInterval(TimeInterval(minutes * 60))
                let time = proposed.formatted(.dateTime.hour().minute())
                let duration = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
                Button { end = proposed } label: {
                    if abs(end.timeIntervalSince(proposed)) < 60 {
                        Label("\(time) · \(duration)", systemImage: "checkmark")
                    } else { Text("\(time) · \(duration)") }
                }
            }
        } label: {
            Label(L("Durata evento"), systemImage: "clock")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func moveStart(_ next: Date) {
        let calendar = Calendar.current
        let previous = start
        start = allDay ? calendar.startOfDay(for: next) : next
        if allDay {
            let days = max(0, calendar.dateComponents([.day], from: previous, to: end).day ?? 0)
            end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        } else {
            end = start.addingTimeInterval(max(60, end.timeIntervalSince(previous)))
        }
    }

    private func setAllDay(_ value: Bool) {
        let range = CalendarAgenda.convertedEventRange(start: start, end: end, allDay: value, calendar: .current)
        start = range.start
        end = range.end
        allDay = value
    }

    private func dateRow(_ label: String, selection: Binding<Date>, showDuration: Bool = false) -> some View {
        GridRow {
            Text(L(label)).foregroundStyle(.secondary)
            CalendarEditorPicker(label: L(label), selection: selection, elements: .yearMonthDay)
            if !allDay {
                CalendarEditorPicker(label: L(label), selection: selection, elements: .hourMinute)
                if showDuration { durationMenu }
            }
        }
    }
}

private struct CalendarEditorPicker: NSViewRepresentable {
    let label: String
    @Binding var selection: Date
    let elements: NSDatePicker.ElementFlags

    final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) { self.selection = selection }

        @objc func changed(_ picker: NSDatePicker) {
            selection.wrappedValue = picker.dateValue
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = elements
        picker.presentsCalendarOverlay = elements == .yearMonthDay
        picker.controlSize = .large
        picker.isBezeled = true
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.selection = $selection
        picker.setAccessibilityLabel(label)
        if picker.dateValue != selection { picker.dateValue = selection }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        nsView.fittingSize
    }
}

struct CalendarWidget: View {
    let agenda: CalendarAgenda
    let displayID: String
    let screen: NSScreen?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let gridTop: CGFloat = 40
    private static let detailHeader: CGFloat = 25
    private static let detailRow: CGFloat = 38
    private static let detailFooter: CGFloat = 24
    private static let addButtonWidth: CGFloat = 24
    private static let monthHeader: CGFloat = 20
    private static let monthControls = [(-1, "chevron.left", "Mese precedente"),
                                        (0, "calendar.badge.clock", "Mese corrente"),
                                        (1, "chevron.right", "Mese successivo")]
    private static let agendaHeader: CGFloat = 20
    private static let agendaSpacing: CGFloat = 5
    private static let agendaRow: CGFloat = 33

    private static func agendaCapacity(_ height: CGFloat) -> Int {
        max(0, Int((height - agendaHeader - agendaSpacing) / (agendaRow + agendaSpacing)))
    }

    private struct DayPage {
        let page: Int
        let pages: Int
        let entries: ArraySlice<CalendarAgenda.Entry>

        init(height: CGFloat, requestedPage: Int, entries: [CalendarAgenda.Entry]) {
            let space = max(0, height - detailHeader)
            let paged = CGFloat(entries.count) * detailRow > space
            let capacity = max(1, Int((space - (paged ? detailFooter : 0)) / detailRow))
            pages = max(1, (entries.count + capacity - 1) / capacity)
            page = min(requestedPage, pages - 1)
            self.entries = entries.dropFirst(page * capacity).prefix(capacity)
        }
    }

    var body: some View {
        Group {
            if agenda.display == .month {
                let selection = agenda.daySelections[displayID]
                ZStack {
                    if let selection {
                        dayView(selection).transition(.move(edge: .trailing))
                    } else {
                        monthView.transition(.move(edge: .leading))
                    }
                }
                .clipped()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: selection != nil)
            } else { agendaView }
        }
        .onAppear { agenda.refresh(force: true) }
    }

    private var agendaView: some View {
        GeometryReader { geometry in
            let capacity = Self.agendaCapacity(geometry.size.height)
            VStack(alignment: .leading, spacing: Self.agendaSpacing) {
                HStack {
                    Label(L("Calendario"), systemImage: "calendar")
                    Spacer()
                    addEventButton(on: nil)
                }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: Self.agendaHeader)
                if agenda.entries.isEmpty {
                    Text(L(agenda.statusMessage)).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(agenda.entries.prefix(capacity)) { event in
                        eventControl(event, height: Self.agendaRow)
                    }
                }
            }
        }
    }

    private func dayView(_ selection: CalendarAgenda.DaySelection) -> some View {
        GeometryReader { geometry in
            let details = DayPage(height: geometry.size.height, requestedPage: selection.page,
                                  entries: agenda.events(on: selection.date))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Button { agenda.closeDay(displayID: displayID) } label: {
                        Image(systemName: "chevron.left").frame(width: 24, height: Self.detailHeader)
                    }.buttonStyle(.plain).accessibilityLabel(L("Torna al mese"))
                    Text(selection.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    addEventButton(on: selection.date)
                }.font(.system(size: 12, weight: .semibold)).frame(height: Self.detailHeader)
                if details.entries.isEmpty {
                    Text(L("Nessun impegno per questo giorno.")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(details.entries) { event in eventControl(event, height: Self.detailRow, showDetails: true) }
                if details.pages > 1 {
                    Spacer(minLength: 0)
                    HStack {
                        Button { agenda.setPage(details.page - 1, displayID: displayID) } label: { Image(systemName: "chevron.left") }
                            .disabled(details.page == 0).accessibilityLabel(L("Pagina precedente"))
                        Spacer()
                        Text("\(details.page + 1) / \(details.pages)").monospacedDigit()
                        Spacer()
                        Button { agenda.setPage(details.page + 1, displayID: displayID) } label: { Image(systemName: "chevron.right") }
                            .disabled(details.page + 1 == details.pages).accessibilityLabel(L("Pagina successiva"))
                    }.buttonStyle(.plain).font(.caption).frame(height: Self.detailFooter)
                }
            }
        }
    }

    private func addEventButton(on date: Date?) -> some View {
        Button { agenda.openEventEditor(on: date, screen: screen) } label: {
            Image(systemName: "plus")
                .frame(width: Self.addButtonWidth, height: date == nil ? Self.agendaHeader : Self.detailHeader)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Nuovo evento"))
    }

    private func eventControl(_ event: CalendarAgenda.Entry, height: CGFloat, showDetails: Bool = false) -> some View {
        Button { agenda.openEventEditor(editing: event, screen: screen) } label: {
            eventRow(event, showDetails: showDetails)
                .frame(height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!event.writable)
        .accessibilityHint(event.writable ? L("Modifica evento") : "")
        .contextMenu {
            ForEach(agenda.eventActions(for: event, screen: screen), id: \.0) { label, action in
                Button(L(label), role: label == "Elimina evento…" ? .destructive : nil, action: action)
            }
        }
    }

    private func eventRow(_ event: CalendarAgenda.Entry, showDetails: Bool = false) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(.tint).frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(event.calendar).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if showDetails, let location = event.location, !location.isEmpty {
                    Text(location).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if !showDetails { Text(event.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
                if event.allDay { Text(L("Tutto il giorno")) }
                else if showDetails, event.end > event.start {
                    Text(event.start...event.end).lineLimit(1)
                } else { Text(event.start, format: .dateTime.hour().minute()) }
            }.font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: !showDetails, vertical: false)
            if event.writable {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }

    private static func monthRowHeight(_ size: CGSize, month: CalendarMonth) -> CGFloat {
        max(14, min(28, (size.height - 44) / CGFloat(month.days.count / 7)))
    }

    static func day(at point: CGPoint, size: CGSize, month: CalendarMonth) -> Date? {
        guard size.width > 0, size.height > 0,
              CGRect(origin: .zero, size: size).contains(point), point.y >= gridTop else { return nil }
        let row = Int((point.y - gridTop) / monthRowHeight(size, month: month))
        let column = Int(point.x * 7 / size.width)
        let index = row * 7 + column
        return month.days.indices.contains(index) ? month.days[index] : nil
    }

    static func clickableDay(at point: CGPoint, size: CGSize, agenda: CalendarAgenda, displayID: String) -> Date? {
        guard agenda.display == .month, agenda.daySelections[displayID] == nil,
              let month = agenda.visibleMonth(displayID: displayID) else { return nil }
        return day(at: point, size: size, month: month)
    }

    private static func monthControlWidth(_ width: CGFloat) -> CGFloat { min(24, width / 4) }

    static func monthNavigation(at point: CGPoint, size: CGSize) -> Int? {
        let width = monthControlWidth(size.width)
        let left = size.width - CGFloat(monthControls.count) * width
        guard width > 0, point.x >= left, point.x < size.width, point.y >= 0, point.y < monthHeader else { return nil }
        return monthControls.indices.first(where: { point.x < left + CGFloat($0 + 1) * width })
            .map { monthControls[$0].0 }
    }

    static func addButtonContains(_ point: CGPoint, size: CGSize, display: CalendarAgenda.Display, showingDay: Bool) -> Bool {
        guard display == .list || showingDay else { return false }
        let height = display == .list ? agendaHeader : detailHeader
        return CGRect(x: max(0, size.width - addButtonWidth), y: 0, width: min(addButtonWidth, size.width), height: height).contains(point)
    }

    static func rowIndex(at y: CGFloat, top: CGFloat, height: CGFloat, spacing: CGFloat) -> Int? {
        let offset = y - top
        guard offset >= 0, offset.truncatingRemainder(dividingBy: height + spacing) < height else { return nil }
        return Int(offset / (height + spacing))
    }

    static func event(at point: CGPoint, size: CGSize, agenda: CalendarAgenda, displayID: String) -> CalendarAgenda.Entry? {
        guard CGRect(origin: .zero, size: size).contains(point) else { return nil }
        if agenda.display == .list {
            guard let index = rowIndex(at: point.y, top: agendaHeader + agendaSpacing, height: agendaRow, spacing: agendaSpacing),
                  index < agendaCapacity(size.height), agenda.entries.indices.contains(index) else { return nil }
            return agenda.entries[index]
        }
        guard let selection = agenda.daySelections[displayID] else { return nil }
        let details = DayPage(height: size.height, requestedPage: selection.page, entries: agenda.events(on: selection.date))
        guard details.pages == 1 || point.y < size.height - detailFooter,
              let row = rowIndex(at: point.y, top: detailHeader, height: detailRow, spacing: 0),
              row < details.entries.count else { return nil }
        return details.entries[details.entries.startIndex + row]
    }

    static func click(_ point: CGPoint, size: CGSize, agenda: CalendarAgenda, displayID: String, screen: NSScreen) {
        guard CGRect(origin: .zero, size: size).contains(point) else { return }
        let selection = agenda.daySelections[displayID]
        if addButtonContains(point, size: size, display: agenda.display, showingDay: selection != nil) {
            agenda.openEventEditor(on: selection?.date, screen: screen)
            return
        }
        if let event = event(at: point, size: size, agenda: agenda, displayID: displayID) {
            if event.writable { agenda.openEventEditor(editing: event, screen: screen) }
            return
        }
        guard agenda.display == .month else { return }
        if let selection {
            let details = DayPage(height: size.height, requestedPage: selection.page, entries: agenda.events(on: selection.date))
            if point.y < detailHeader, point.x < 24 {
                agenda.closeDay(displayID: displayID)
            } else if details.pages > 1, point.y >= size.height - detailFooter {
                let next = details.page + (point.x < size.width / 2 ? -1 : 1)
                agenda.setPage(min(details.pages - 1, max(0, next)), displayID: displayID)
            }
            return
        }
        if let offset = monthNavigation(at: point, size: size) {
            agenda.moveMonth(by: offset, displayID: displayID)
        } else if let day = clickableDay(at: point, size: size, agenda: agenda, displayID: displayID) {
            agenda.openDay(day, displayID: displayID, screen: screen)
        }
    }

    private var monthView: some View {
        TimelineView(.everyMinute) { context in
            if let month = agenda.visibleMonth(displayID: displayID, now: context.date) {
                GeometryReader { geometry in
                    let rowHeight = Self.monthRowHeight(geometry.size, month: month)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            ViewThatFits(in: .horizontal) {
                                Text(month.interval.start, format: .dateTime.month(.wide).year()).fixedSize()
                                Text(month.interval.start, format: .dateTime.month(.abbreviated).year()).lineLimit(1)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 0)
                            HStack(spacing: 0) {
                                ForEach(Self.monthControls, id: \.0) { offset, icon, label in
                                    Button { agenda.moveMonth(by: offset, displayID: displayID) } label: {
                                        Image(systemName: icon)
                                            .font(.system(size: 10, weight: .semibold))
                                            .frame(width: Self.monthControlWidth(geometry.size.width), height: Self.monthHeader)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L(label))
                                    .help(L(label))
                                }
                            }
                        }.frame(height: Self.monthHeader)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7), spacing: 0) {
                            ForEach(0..<7, id: \.self) { index in
                                Text(month.weekdays[index]).font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary).frame(height: 16)
                            }
                            ForEach(month.days.indices, id: \.self) { index in
                                if let day = month.days[index] {
                                    let today = month.calendar.isDate(day, inSameDayAs: context.date)
                                    let hasEvents = agenda.markedDays.contains(day)
                                    let hovered = agenda.hoveredDays[displayID] == day
                                    Button { agenda.openDay(day, displayID: displayID, screen: screen) } label: {
                                        Text(day, format: .dateTime.day())
                                        .font(.system(size: 11, weight: today ? .bold : .regular)).monospacedDigit()
                                        .frame(maxWidth: .infinity).frame(height: rowHeight)
                                        .contentShape(Rectangle())
                                        .background {
                                            if today || hovered {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(hovered ? Color.accentColor.opacity(0.42) : Color.accentColor.opacity(0.25))
                                            }
                                        }
                                        .overlay {
                                            if hovered { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.52)) }
                                        }
                                        .overlay(alignment: .bottom) {
                                            if hasEvents { Circle().fill(.tint).frame(width: 4, height: 4) }
                                        }
                                    }.buttonStyle(.plain)
                                        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                                        .accessibilityValue(hasEvents ? L("Con impegni") : "")
                                } else {
                                    Color.clear.frame(height: rowHeight).accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CalendarMonth {
    let calendar: Calendar
    let interval: DateInterval
    let weekdays: [String]
    let days: [Date?]

    init?(date: Date, calendar: Calendar) {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return nil }
        self.calendar = calendar
        self.interval = interval
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        weekdays = Array(symbols.dropFirst(first)) + Array(symbols.prefix(first))
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: leading)
        cells += range.indices.map { calendar.date(byAdding: .day, value: $0 - range.startIndex, to: interval.start) }
        cells += Array<Date?>(repeating: nil, count: (7 - cells.count % 7) % 7)
        days = cells
    }

    func overlaps(_ day: Date, start: Date, end: Date) -> Bool {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return false }
        return start < interval.end && (start == end ? start >= interval.start : end > interval.start)
    }
}
