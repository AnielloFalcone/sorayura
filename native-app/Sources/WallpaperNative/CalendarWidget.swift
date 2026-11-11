import EventKit
import SwiftUI

@MainActor @Observable final class CalendarAgenda {
    struct CalendarChoice: Identifiable, Equatable {
        let id: String
        let title: String
        let account: String
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let title: String
        let calendar: String
        let start: Date
        let end: Date
        let allDay: Bool
        let location: String?
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
    private(set) var selected: Set<String>
    private(set) var calendars: [CalendarChoice] = []
    private(set) var entries: [Entry] = []
    private(set) var markedDays: Set<Date> = []
    private(set) var daySelections: [String: DaySelection] = [:]
    private var monthEntries: [Entry] = []

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
        defaults?.set(value.rawValue, forKey: Self.displayKey)
        refresh(force: true)
    }

    func openDay(_ date: Date, displayID: String) {
        guard markedDays.contains(date) else { return }
        daySelections[displayID] = DaySelection(date: date)
    }

    func closeDay(displayID: String) {
        daySelections.removeValue(forKey: displayID)
    }

    func setPage(_ page: Int, displayID: String) {
        daySelections[displayID]?.page = page
    }

    func events(on date: Date) -> [Entry] {
        guard let month = CalendarMonth(date: date, calendar: .current) else { return [] }
        return monthEntries.filter { month.overlaps(date, start: $0.start, end: $0.end) }
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
            if !monthEntries.isEmpty { monthEntries = [] }
            if !daySelections.isEmpty { daySelections.removeAll() }
            return
        }

        let available = store.calendars(for: .event)
        let choices = available.map {
            CalendarChoice(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title)
        }.sorted {
            ($0.account + "\n" + $0.title).localizedStandardCompare($1.account + "\n" + $1.title) == .orderedAscending
        }
        if calendars != choices { calendars = choices }
        let active = available.filter { selected.contains($0.calendarIdentifier) }
        guard !active.isEmpty, let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else {
            if !entries.isEmpty { entries = [] }
            if !markedDays.isEmpty { markedDays = [] }
            if !monthEntries.isEmpty { monthEntries = [] }
            if !daySelections.isEmpty { daySelections.removeAll() }
            return
        }
        if display == .month, let month = CalendarMonth(date: now, calendar: .current) {
            let predicate = store.predicateForEvents(withStart: month.interval.start, end: month.interval.end, calendars: active)
            let events = store.events(matching: predicate).filter { $0.status != .canceled }
                .sorted { $0.compareStartDate(with: $1) == .orderedAscending }
            let details = events.map(Self.entry)
            if monthEntries != details { monthEntries = details }
            let marks = Set(month.days.compactMap { day -> Date? in
                guard let day, events.contains(where: { month.overlaps(day, start: $0.startDate, end: $0.endDate) }) else { return nil }
                return day
            })
            if markedDays != marks { markedDays = marks }
            if daySelections.values.contains(where: { !month.interval.contains($0.date) || $0.date == month.interval.end }) {
                daySelections = daySelections.filter { month.interval.contains($0.value.date) && $0.value.date < month.interval.end }
            }
            if !entries.isEmpty { entries = [] }
            return
        }
        if !markedDays.isEmpty { markedDays = [] }
        if !monthEntries.isEmpty { monthEntries = [] }
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
              calendar: event.calendar.title, start: event.startDate, end: event.endDate, allDay: event.isAllDay,
              location: event.location)
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

struct CalendarWidget: View {
    let agenda: CalendarAgenda
    let displayID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let gridTop: CGFloat = 40
    private static let detailHeader: CGFloat = 25
    private static let detailRow: CGFloat = 38
    private static let detailFooter: CGFloat = 24

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
            let capacity = max(0, Int((geometry.size.height - 25) / 38))
            VStack(alignment: .leading, spacing: 5) {
                Label(L("Calendario"), systemImage: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 20)
                if agenda.entries.isEmpty {
                    Text(L(agenda.statusMessage)).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(agenda.entries.prefix(capacity)) { event in
                        eventRow(event).frame(height: 33)
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
                }.font(.system(size: 12, weight: .semibold)).frame(height: Self.detailHeader)
                if details.entries.isEmpty {
                    Text(L("Nessun impegno per questo giorno.")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(details.entries) { event in eventRow(event, showDetails: true).frame(height: Self.detailRow) }
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
        }
    }

    private static func monthRowHeight(_ size: CGSize, month: CalendarMonth) -> CGFloat {
        max(14, min(28, (size.height - 44) / CGFloat(month.days.count / 7)))
    }

    static func click(_ point: CGPoint, size: CGSize, agenda: CalendarAgenda, displayID: String) {
        guard agenda.display == .month, CGRect(origin: .zero, size: size).contains(point) else { return }
        if let selection = agenda.daySelections[displayID] {
            if point.y < detailHeader, point.x < 24 {
                agenda.closeDay(displayID: displayID)
            } else if point.y >= size.height - detailFooter {
                let details = DayPage(height: size.height, requestedPage: selection.page, entries: agenda.events(on: selection.date))
                guard details.pages > 1 else { return }
                let next = details.page + (point.x < size.width / 2 ? -1 : 1)
                agenda.setPage(min(details.pages - 1, max(0, next)), displayID: displayID)
            }
            return
        }
        guard point.y >= gridTop, let month = CalendarMonth(date: .now, calendar: .current) else { return }
        let row = Int((point.y - gridTop) / monthRowHeight(size, month: month))
        let column = Int(point.x * 7 / size.width)
        let index = row * 7 + column
        if month.days.indices.contains(index), let day = month.days[index] {
            agenda.openDay(day, displayID: displayID)
        }
    }

    private var monthView: some View {
        TimelineView(.everyMinute) { context in
            if let month = CalendarMonth(date: context.date, calendar: .current) {
                GeometryReader { geometry in
                    let rowHeight = Self.monthRowHeight(geometry.size, month: month)
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text(month.interval.start, format: .dateTime.month(.wide).year())
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "calendar")
                        }.font(.system(size: 12, weight: .semibold)).frame(height: 20)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7), spacing: 0) {
                            ForEach(0..<7, id: \.self) { index in
                                Text(month.weekdays[index]).font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary).frame(height: 16)
                            }
                            ForEach(month.days.indices, id: \.self) { index in
                                if let day = month.days[index] {
                                    let today = month.calendar.isDate(day, inSameDayAs: context.date)
                                    let hasEvents = agenda.markedDays.contains(day)
                                    Button { agenda.openDay(day, displayID: displayID) } label: {
                                        Text(day, format: .dateTime.day())
                                        .font(.system(size: 11, weight: today ? .bold : .regular)).monospacedDigit()
                                        .frame(maxWidth: .infinity).frame(height: rowHeight)
                                        .background {
                                            if today { RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.32)) }
                                        }
                                        .overlay(alignment: .bottom) {
                                            if hasEvents { Circle().fill(.tint).frame(width: 4, height: 4) }
                                        }
                                    }.buttonStyle(.plain).disabled(!hasEvents)
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
