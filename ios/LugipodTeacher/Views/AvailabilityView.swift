import SwiftUI

/// The weekly hours editor. On an iPad (wide) the controls sit in a card on the side and the week
/// fills the rest; on a phone the controls shrink to one row above the week. The grid never lives
/// inside a scroll view, so touching it can only mean "edit hours".
struct AvailabilityView: View {
    @StateObject private var model = AvailabilityModel()

    var body: some View {
        ZStack {
            ScreenBackground()
            switch model.phase {
            case .loading:
                ProgressView().controlSize(.large)
            case .failed:
                EmptyState(pose: .peek, title: "לא הצלחנו לטעון את השעות",
                           message: "בדקו חיבור לאינטרנט ונסו שוב.", actionTitle: "נסו שוב") {
                    Task { await model.load() }
                }
                .frame(maxWidth: 460).padding(20)
            case .ready:
                editor
            }
        }
        .task { await model.load() }
        .alert("שגיאה", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("אישור", role: .cancel) {}
        } message: { Text(model.error ?? "") }
    }

    // MARK: Layout

    private var editor: some View {
        GeometryReader { geo in
            if geo.size.width >= 880 {
                HStack(alignment: .top, spacing: 18) {
                    ScrollView {
                        VStack(spacing: 14) { sideControls }
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: 330)
                    WeekGridCard(model: model, availableHeight: geo.size.height - 28)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
            } else {
                VStack(spacing: 12) {
                    compactControls
                    WeekGridCard(model: model, availableHeight: geo.size.height - 150)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    // MARK: Controls

    @ViewBuilder private var sideControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("השעות שלי").font(.heebo(30, 800)).foregroundStyle(Theme.ink)
            Text("סמנו מתי תוכלו ללמד. בלי שעות זמינות לא נוכל לשבץ אתכם לקבוצות.")
                .font(.heebo(15, 500)).foregroundStyle(Theme.slate500)
            modePicker
            Text(model.mode == .available
                 ? "צבעו את כל השעות שבהן אתם פנויים ללמד."
                 : "בחרו מתוך השעות הזמינות את אלה שתעדיפו. שעות שאינן זמינות נעולות.")
                .font(.heebo(13, 500)).foregroundStyle(Theme.slate500)
            if !(model.mode == .available ? model.available.isEmpty : model.preferred.isEmpty) {
                Button("ניקוי הכל") { model.clearCurrent() }
                    .buttonStyle(SoftButtonStyle(fg: Theme.rose600, bg: Theme.rose50))
            }
        }
        .card(padding: 20)

        if model.available.isEmpty { noHoursBanner }

        lessonTip

        if model.mode == .available, !model.hotToOpen.isEmpty { hotCard }

        legend
        saveButton
    }

    private var compactControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                modePicker
                saveButton.frame(width: 120)
            }
            if model.mode == .available, !model.hotToOpen.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { hotChips }
                }
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            modeButton(.available, title: "זמין", icon: "circle.fill", color: Theme.emerald500, id: "mode-available")
            modeButton(.preferred, title: "מועדף", icon: "star.fill", color: Theme.brand600, id: "mode-preferred")
        }
        .padding(5)
        .background(Theme.slate100, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func modeButton(_ mode: AvailabilityModel.Mode, title: String, icon: String, color: Color, id: String) -> some View {
        let selected = model.mode == mode
        let count = mode == .available ? model.available.count : model.preferred.count
        return Button { model.mode = mode } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                    Text(title).font(.heebo(15, 800))
                }
                Text(hours(count)).font(.heebo(12, 600)).foregroundStyle(Theme.slate500)
            }
            .foregroundStyle(selected ? Theme.ink : Theme.slate500)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(selected ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: selected ? Theme.shadowSoft2 : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel("\(title) \(hours(count))")
    }

    private var noHoursBanner: some View {
        Label("עדיין לא סימנתם שעות זמינות. בלי שעות לא נוכל לשבץ אתכם לקבוצות.", systemImage: "exclamationmark.triangle.fill")
            .font(.heebo(14, 700)).foregroundStyle(Theme.amber800)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.amber50, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.amber200, lineWidth: 1))
    }

    /// The parents' complaint, answered for teachers too: a lesson is three squares.
    private var lessonTip: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("💡").font(.system(size: 22))
            VStack(alignment: .leading, spacing: 4) {
                Text("שיעור = 90 דקות = 3 משבצות").font(.heebo(15, 800)).foregroundStyle(Theme.sky800)
                Text("לחיצה על משבצת משלימה לבד לשלוש. החזיקו והחליקו כדי לצבוע כמה שעות ברצף.")
                    .font(.heebo(13, 500)).foregroundStyle(Theme.sky800.opacity(0.85))
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sky50, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.sky200, lineWidth: 1))
    }

    private var hotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ביקוש חם. שווה לפתוח", systemImage: "flame.fill")
                .font(.heebo(15, 800)).foregroundStyle(Theme.rose600)
            Text("תלמידים מחפשים שיעור בשעות האלה. פתיחה שלהן מגדילה את הסיכוי לשיבוץ.")
                .font(.heebo(13, 500)).foregroundStyle(Theme.slate600)
            FlowLayout(spacing: 8) { hotChips }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.rose50, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(hex: 0xFECDD3), lineWidth: 1))
    }

    @ViewBuilder private var hotChips: some View {
        ForEach(model.hotToOpen, id: \.slot) { h in
            Button { model.openHot(h.slot) } label: {
                Text("+ \(Week.label(slot: h.slot)) · ~\(Week.matchPercent(weight: h.weight))%")
                    .font(.heebo(13, 800)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(h.weight >= 9 ? Theme.rose500 : Theme.amber500, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.mode == .available {
                legendRow(Theme.emerald500, "זמין")
                legendRow(Theme.amber400, "פחות משיעור שלם. השלימו לשלוש משבצות")
                legendRow(Theme.orange100, "ביקוש חם (בשעה שעוד לא פתחתם)", border: Theme.orange300)
            } else {
                legendRow(Theme.brand600, "מועדף")
                legendRow(Theme.emerald100, "זמין, לא מועדף", border: Theme.emerald200)
                legendRow(Theme.slate100, "לא זמין (נעול)")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0, radius: 22)
    }

    private func legendRow(_ color: Color, _ text: String, border: Color? = nil) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(border ?? .clear, lineWidth: 1))
            Text(text).font(.heebo(13, 600)).foregroundStyle(Theme.slate600)
        }
    }

    private var saveButton: some View {
        VStack(spacing: 8) {
            Button { Task { await model.save() } } label: {
                HStack(spacing: 8) {
                    if model.saving { ProgressView().tint(.white) }
                    Text(model.justSaved ? "נשמר ✓" : "שמירה")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.dirty || model.saving)
            .accessibilityIdentifier("save-hours")
            if model.dirty {
                Text("יש שינויים שלא נשמרו").font(.heebo(12, 600)).foregroundStyle(Theme.amber800)
            }
        }
    }

    private func hours(_ slots: Int) -> String {
        let h = Double(slots) / 2
        return h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h)) ש׳" : String(format: "%.1f ש׳", h)
    }
}

/// Chips that wrap onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The week as a card: 7 day columns (Sunday on the right) x half-hour rows (09:00–22:00).
/// Laid out left-to-right internally so touch positions are plain x/y arithmetic.
struct WeekGridCard: View {
    @ObservedObject var model: AvailabilityModel
    let availableHeight: CGFloat

    @State private var painting = false
    @State private var paintValue = true
    @State private var lastTouched: Int?

    private let labelWidth: CGFloat = 50
    private let headerHeight: CGFloat = 50
    private let padding: CGFloat = 14

    private var cellHeight: CGFloat {
        let rows = CGFloat(Week.rows.count)
        return min(38, max(16, (availableHeight - headerHeight - padding * 2 - 6) / rows))
    }

    private var todayIndex: Int { Calendar.current.component(.weekday, from: Date()) - 1 }

    var body: some View {
        GeometryReader { geo in
            let cellWidth = max(1, (geo.size.width - padding * 2 - labelWidth) / CGFloat(Week.days))
            let analysis = model.analysis()
            VStack(spacing: 0) {
                header(cellWidth)
                rows(cellWidth, analysis: analysis)
                    .contentShape(Rectangle())
                    .gesture(drag(cellWidth))
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("week-grid")
                    .accessibilityLabel("לוח שעות שבועי")
            }
            .padding(padding)
            .frame(width: geo.size.width, alignment: .top)
        }
        .frame(height: min(availableHeight, headerHeight + cellHeight * CGFloat(Week.rows.count) + padding * 2 + 6))
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
        .shadow(color: Theme.shadowSoft1, radius: 1, y: 1)
        .shadow(color: Theme.shadowSoft2, radius: 8, y: 4)
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: Touch

    /// A tap and a paint are the same gesture: no movement = tap (fills a lesson block), movement =
    /// paint every slot under the finger with the value the first slot flips to.
    private func drag(_ cellWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
                if !painting, moved > 10 {
                    painting = true
                    if let s = slot(at: v.startLocation, cellWidth) {
                        paintValue = !model.isSet(s)
                        apply(s)
                    }
                }
                if painting, let s = slot(at: v.location, cellWidth), s != lastTouched { apply(s) }
            }
            .onEnded { v in
                if !painting, let s = slot(at: v.startLocation, cellWidth) {
                    model.tap(s)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                painting = false
                lastTouched = nil
            }
    }

    private func apply(_ s: Int) {
        lastTouched = s
        guard model.isEditable(s), model.isSet(s) != paintValue else { return }
        model.set(s, on: paintValue)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Column 0 is the leftmost = Saturday; Sunday sits next to the time labels on the right.
    private func day(forColumn col: Int) -> Int { Week.days - 1 - col }

    private func slot(at p: CGPoint, _ cellWidth: CGFloat) -> Int? {
        guard p.x >= 0, p.y >= 0 else { return nil }
        let col = Int(p.x / cellWidth)
        let r = Int(p.y / cellHeight)
        guard col < Week.days, r < Week.rows.count else { return nil }
        return Week.slot(day: day(forColumn: col), row: Week.firstRow + r)
    }

    // MARK: Drawing

    private func header(_ cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<Week.days, id: \.self) { col in
                let d = day(forColumn: col)
                let hours = model.hours(onDay: d)
                let isToday = d == todayIndex
                VStack(spacing: 2) {
                    Text(Week.dayNames[d]).font(.heebo(14, 800))
                        .foregroundStyle(isToday ? .white : Theme.ink)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(hours > 0 ? hoursLabel(hours) : "·")
                        .font(.heebo(11, 700))
                        .foregroundStyle(isToday ? .white.opacity(0.85) : (hours > 0 ? Theme.emerald600 : Theme.slate300))
                }
                .frame(width: cellWidth - 4, height: headerHeight - 8)
                .background(isToday ? Theme.brand600 : Theme.slate50, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(width: cellWidth, height: headerHeight)
            }
            Color.clear.frame(width: labelWidth, height: headerHeight)
        }
    }

    private func hoursLabel(_ h: Double) -> String {
        h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h)) ש׳" : String(format: "%.1f ש׳", h)
    }

    private func rows(_ cellWidth: CGFloat, analysis: (incomplete: Set<Int>, suggested: Set<Int>)) -> some View {
        VStack(spacing: 0) {
            ForEach(Week.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<Week.days, id: \.self) { col in
                        cell(Week.slot(day: day(forColumn: col), row: row), analysis: analysis)
                            .frame(width: cellWidth, height: cellHeight)
                    }
                    Text(row % 2 == 0 ? Week.time(row: row) : "")
                        .font(.heebo(11, 600).monospacedDigit())
                        .foregroundStyle(Theme.slate400)
                        .frame(width: labelWidth, height: cellHeight, alignment: .topTrailing)
                        .offset(y: -5)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ s: Int, analysis: (incomplete: Set<Int>, suggested: Set<Int>)) -> some View {
        let style = cellStyle(s, analysis: analysis)
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(style.fill)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(style.border, style: StrokeStyle(lineWidth: 1, dash: style.dashed ? [3, 3] : []))
            )
            .overlay {
                if let mark = style.mark, cellHeight >= 20 { Text(mark).font(.system(size: 10, weight: .bold)).foregroundStyle(style.markColor) }
            }
            .padding(1.5)
    }

    private struct CellStyle {
        var fill: Color
        var border: Color = .clear
        var dashed = false
        var mark: String?
        var markColor: Color = .white
    }

    private func cellStyle(_ s: Int, analysis: (incomplete: Set<Int>, suggested: Set<Int>)) -> CellStyle {
        let incomplete = analysis.incomplete.contains(s)
        switch model.mode {
        case .available:
            if model.available.contains(s) {
                return incomplete ? CellStyle(fill: Theme.amber400, mark: "!") : CellStyle(fill: Theme.emerald500)
            }
            if analysis.suggested.contains(s) { return CellStyle(fill: Theme.brand50, border: Theme.brand400, dashed: true, mark: "+", markColor: Theme.brand600) }
            if model.isHot(s) { return CellStyle(fill: Theme.orange100, border: Theme.orange300, mark: "🔥") }
            return CellStyle(fill: Theme.slate50, border: Theme.slate200)
        case .preferred:
            if model.preferred.contains(s) {
                return incomplete ? CellStyle(fill: Theme.amber400, mark: "!") : CellStyle(fill: Theme.brand600, mark: "★")
            }
            if analysis.suggested.contains(s) { return CellStyle(fill: Theme.brand50, border: Theme.brand400, dashed: true, mark: "+", markColor: Theme.brand600) }
            if model.available.contains(s) { return CellStyle(fill: Theme.emerald100, border: Theme.emerald200) }
            return CellStyle(fill: Theme.slate100)
        }
    }
}
