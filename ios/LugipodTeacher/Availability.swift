import Foundation

/// The week as the backend models it: 7 days x 48 half-hour slots, slot = day * 48 + halfHour,
/// day 0 = Sunday, halfHour 0 = 00:00. Same numbers as the website's availability grid.
enum Week {
    static let slotsPerDay = 48
    static let days = 7
    /// The editable window is 09:00 to 22:00, like the website.
    static let firstRow = 18
    static let lastRow = 43
    static let rows = Array(firstRow...lastRow)
    /// One lesson is 90 minutes = 3 half-hour slots in a row.
    static let sessionSlots = 3
    static let dayNames = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"]

    static func slot(day: Int, row: Int) -> Int { day * slotsPerDay + row }
    static func day(of slot: Int) -> Int { slot / slotsPerDay }
    static func row(of slot: Int) -> Int { slot % slotsPerDay }

    static func time(row: Int) -> String {
        String(format: "%02d:%@", row / 2, row % 2 == 0 ? "00" : "30")
    }

    static func label(slot: Int) -> String {
        "\(dayNames[day(of: slot)]) \(time(row: row(of: slot)))"
    }

    /// Opening a hot slot opens a full 90-minute block (3 slots) on that day.
    static func block(from slot: Int) -> [Int] {
        [slot, slot + 1, slot + 2].filter { day(of: $0) == day(of: slot) }
    }

    /// A rough instant-match likelihood from a slot's demand weight (a nudge, capped).
    static func matchPercent(weight: Double) -> Int { Int(min(95, 35 + weight * 9)) }
}

struct HotSlot: Decodable, Equatable {
    let slot: Int
    let weight: Double
}

struct AvailabilityResponse: Decodable {
    let available: [Int]
    let preferred: [Int]
    let hot: [HotSlot]
}

/// The teacher's weekly hours: "available" (every slot they can teach) and "preferred" (the
/// subset students are steered toward, always inside available).
@MainActor
final class AvailabilityModel: ObservableObject {
    enum Mode: Hashable { case available, preferred }
    enum Phase: Equatable { case loading, ready, failed }

    @Published var mode: Mode = .available
    @Published private(set) var available: Set<Int> = []
    @Published private(set) var preferred: Set<Int> = []
    @Published private(set) var hot: [HotSlot] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var saving = false
    @Published private(set) var justSaved = false
    @Published var error: String?

    private var savedAvailable: Set<Int> = []
    private var savedPreferred: Set<Int> = []

    var dirty: Bool { available != savedAvailable || preferred != savedPreferred }

    /// Hot slots the teacher has not opened yet, hottest first.
    var hotToOpen: [HotSlot] { Array(hot.filter { !available.contains($0.slot) }.prefix(6)) }

    func isHot(_ slot: Int) -> Bool { hot.contains { $0.slot == slot } }

    // MARK: - Editing

    func isSet(_ slot: Int) -> Bool {
        mode == .available ? available.contains(slot) : preferred.contains(slot)
    }

    /// Preferred hours can only be picked from the available ones.
    func isEditable(_ slot: Int) -> Bool {
        mode == .available || available.contains(slot)
    }

    /// A tap, as on the website: an empty half-hour fills out to a whole 90-minute lesson block
    /// (forward first, then backward, through editable hours only); a filled one clears just itself.
    func tap(_ slot: Int) {
        guard isEditable(slot) else { return }
        if isSet(slot) { set(slot, on: false); return }

        let day = Week.day(of: slot), row = Week.row(of: slot)
        func has(_ r: Int) -> Bool { isSet(Week.slot(day: day, row: r)) }
        func usable(_ r: Int) -> Bool {
            r >= Week.firstRow && r <= Week.lastRow && isEditable(Week.slot(day: day, row: r))
        }
        var lo = row, hi = row
        while has(lo - 1) { lo -= 1 }
        while has(hi + 1) { hi += 1 }
        var added = [slot]
        while hi - lo + 1 < Week.sessionSlots, usable(hi + 1), !has(hi + 1) {
            hi += 1; added.append(Week.slot(day: day, row: hi))
        }
        while hi - lo + 1 < Week.sessionSlots, usable(lo - 1), !has(lo - 1) {
            lo -= 1; added.append(Week.slot(day: day, row: lo))
        }
        for s in added { set(s, on: true) }
    }

    /// Runs shorter than a lesson (marked amber) and the empty slots that would complete them
    /// (suggested, dashed), for the layer being edited.
    func analysis() -> (incomplete: Set<Int>, suggested: Set<Int>) {
        let current = mode == .available ? available : preferred
        var incomplete = Set<Int>(), suggested = Set<Int>()
        for day in 0..<Week.days {
            let rows = Week.rows.filter { current.contains(Week.slot(day: day, row: $0)) }
            var i = 0
            while i < rows.count {
                var j = i
                while j + 1 < rows.count, rows[j + 1] == rows[j] + 1 { j += 1 }
                let length = j - i + 1
                if length < Week.sessionSlots {
                    for r in rows[i]...rows[j] { incomplete.insert(Week.slot(day: day, row: r)) }
                    var need = Week.sessionSlots - length
                    var r = rows[j] + 1
                    while need > 0, r <= Week.lastRow {
                        let s = Week.slot(day: day, row: r)
                        if current.contains(s) || !isEditable(s) { break }
                        suggested.insert(s); need -= 1; r += 1
                    }
                    r = rows[i] - 1
                    while need > 0, r >= Week.firstRow {
                        let s = Week.slot(day: day, row: r)
                        if current.contains(s) || !isEditable(s) { break }
                        suggested.insert(s); need -= 1; r -= 1
                    }
                }
                i = j + 1
            }
        }
        return (incomplete, suggested)
    }

    func hours(onDay day: Int) -> Double {
        let current = mode == .available ? available : preferred
        return Double(current.filter { Week.day(of: $0) == day }.count) / 2
    }

    func set(_ slot: Int, on: Bool) {
        guard isEditable(slot) else { return }
        switch mode {
        case .available:
            if on { available.insert(slot) } else { available.remove(slot); preferred.remove(slot) }
        case .preferred:
            if on { preferred.insert(slot) } else { preferred.remove(slot) }
        }
        justSaved = false
    }

    func openHot(_ slot: Int) {
        available.formUnion(Week.block(from: slot))
        justSaved = false
    }

    func clearCurrent() {
        switch mode {
        case .available: available = []; preferred = []
        case .preferred: preferred = []
        }
        justSaved = false
    }

    // MARK: - Server

    func load() async {
        if phase == .ready { return }
        phase = .loading
        do {
            let r = try await API.get("/api/native/availability", as: AvailabilityResponse.self)
            available = Set(r.available)
            preferred = Set(r.preferred).intersection(available)
            savedAvailable = available
            savedPreferred = preferred
            hot = r.hot
            phase = .ready
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            phase = .failed
        }
    }

    func save() async {
        guard dirty, !saving else { return }
        saving = true
        defer { saving = false }
        let avail = available
        let pref = preferred.intersection(avail)
        do {
            _ = try await API.post("/api/native/availability",
                                   json: ["available": avail.sorted(), "preferred": pref.sorted()])
            preferred = pref
            savedAvailable = avail
            savedPreferred = pref
            justSaved = true
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            self.error = "השמירה נכשלה. בדקו חיבור ונסו שוב."
        }
    }
}
