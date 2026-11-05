import SwiftUI

/// The weekly hours editor. Tap a half-hour to flip it; press and hold, then slide to paint a
/// run of hours (a quick swipe still scrolls the page).
struct AvailabilityView: View {
    @StateObject private var model = AvailabilityModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView()
                case .failed:
                    ContentUnavailableView {
                        Label("לא הצלחנו לטעון את השעות", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("נסו שוב") { Task { await model.load() } }.buttonStyle(.borderedProminent)
                    }
                case .ready:
                    editor
                }
            }
            .navigationTitle("השעות שלי")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.save() }
                    } label: {
                        if model.saving { ProgressView() } else { Text(model.justSaved ? "נשמר ✓" : "שמירה").fontWeight(.semibold) }
                    }
                    .disabled(!model.dirty || model.saving)
                }
            }
            .alert("שגיאה", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("אישור", role: .cancel) {}
            } message: { Text(model.error ?? "") }
        }
        .task { await model.load() }
    }

    private var editor: some View {
        ScrollView {
            VStack(spacing: 16) {
                if model.available.isEmpty {
                    Label("עדיין לא סימנתם שעות זמינות. בלי שעות לא נוכל לשבץ אתכם לקבוצות.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                Picker("סוג שעות", selection: $model.mode) {
                    Text("זמין · \(hours(model.available.count))").tag(AvailabilityModel.Mode.available)
                    Text("מועדף · \(hours(model.preferred.count))").tag(AvailabilityModel.Mode.preferred)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(model.mode == .available
                         ? "צבעו את כל השעות שבהן אתם פנויים ללמד."
                         : "בחרו מתוך השעות הזמינות את אלה שתעדיפו. שעות שאינן זמינות נעולות.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if !(model.mode == .available ? model.available.isEmpty : model.preferred.isEmpty) {
                        Button("ניקוי", role: .destructive) { model.clearCurrent() }.font(.footnote)
                    }
                }

                if model.mode == .available, !model.hotToOpen.isEmpty { hotSection }

                WeekGrid(model: model)

                Text("הקישו כדי לסמן או לבטל. החזיקו והחליקו כדי לצבוע כמה שעות ברצף.")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ביקוש חם. שווה לפתוח", systemImage: "flame.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(.orange)
            Text("תלמידים מחפשים שיעור בשעות האלה. פתיחה שלהן מגדילה את הסיכוי לשיבוץ.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.hotToOpen, id: \.slot) { h in
                        Button { model.openHot(h.slot) } label: {
                            Text("+ \(Week.label(slot: h.slot)) · ~\(Week.matchPercent(weight: h.weight))%")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.bordered).tint(.orange)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func hours(_ slots: Int) -> String {
        let h = Double(slots) / 2
        return h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h)) ש׳" : String(format: "%.1f ש׳", h)
    }
}

/// 7 columns (Sunday on the right, like the rest of the Hebrew UI) x half-hour rows.
/// Laid out left-to-right internally so the touch math is plain x/y arithmetic.
struct WeekGrid: View {
    @ObservedObject var model: AvailabilityModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var paintValue: Bool?
    @State private var lastPainted: Int?
    @State private var paintEndedAt = Date.distantPast

    private let labelWidth: CGFloat = 46
    private let headerHeight: CGFloat = 28
    private var cellHeight: CGFloat { sizeClass == .regular ? 30 : 26 }

    var body: some View {
        GeometryReader { geo in
            let cellWidth = max(1, (geo.size.width - labelWidth) / CGFloat(Week.days))
            VStack(spacing: 0) {
                header(cellWidth)
                rows(cellWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard Date().timeIntervalSince(paintEndedAt) > 0.3,
                                  let s = slot(at: value.location, cellWidth: cellWidth),
                                  model.isEditable(s) else { return }
                            model.set(s, on: !model.isSet(s))
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    )
                    .gesture(
                        LongPressGesture(minimumDuration: 0.2)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                guard case .second(true, let drag?) = value,
                                      let s = slot(at: drag.location, cellWidth: cellWidth) else { return }
                                if paintValue == nil { paintValue = !model.isSet(s) }
                                guard lastPainted != s, let on = paintValue else { return }
                                lastPainted = s
                                if model.isEditable(s) {
                                    model.set(s, on: on)
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            }
                            .onEnded { _ in
                                paintValue = nil
                                lastPainted = nil
                                paintEndedAt = Date()
                            }
                    )
            }
        }
        .frame(height: headerHeight + cellHeight * CGFloat(Week.rows.count))
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - Layout

    /// Column 0 is the leftmost = Saturday; Sunday sits next to the time labels on the right.
    private func day(forColumn col: Int) -> Int { Week.days - 1 - col }

    private func header(_ cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<Week.days, id: \.self) { col in
                Text(Week.dayNames[day(forColumn: col)])
                    .font(.caption.weight(.semibold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .frame(width: cellWidth, height: headerHeight)
            }
            Color.clear.frame(width: labelWidth, height: headerHeight)
        }
    }

    private func rows(_ cellWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Week.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<Week.days, id: \.self) { col in
                        let s = Week.slot(day: day(forColumn: col), row: row)
                        Rectangle()
                            .fill(color(for: s))
                            .frame(width: cellWidth, height: cellHeight)
                            .overlay(alignment: .top) {
                                if row % 2 == 0 { Rectangle().fill(Color(.separator)).frame(height: 0.5) }
                            }
                            .overlay(alignment: .leading) { Rectangle().fill(Color(.systemBackground)).frame(width: 1) }
                    }
                    Text(row % 2 == 0 ? Week.time(row: row) : "")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, height: cellHeight, alignment: .topTrailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func slot(at p: CGPoint, cellWidth: CGFloat) -> Int? {
        guard p.x >= 0, p.y >= 0 else { return nil }
        let col = Int(p.x / cellWidth)
        let r = Int(p.y / cellHeight)
        guard col < Week.days, r < Week.rows.count else { return nil }
        return Week.slot(day: day(forColumn: col), row: Week.firstRow + r)
    }

    private func color(for s: Int) -> Color {
        switch model.mode {
        case .available:
            if model.available.contains(s) { return .green.opacity(0.75) }
            if model.isHot(s) { return .orange.opacity(0.28) }
            return Color(.secondarySystemFill)
        case .preferred:
            if model.preferred.contains(s) { return .indigo }
            if model.available.contains(s) { return .green.opacity(0.3) }
            return Color(.tertiarySystemFill)
        }
    }
}
