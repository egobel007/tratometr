import SwiftUI
import SwiftData

struct StatsView: View {
    @EnvironmentObject private var app: AppState
    let items: [SpendItem]
    let isDemo: Bool

    @AppStorage("currency") private var currency = "RUB"
    @AppStorage("budget") private var budget: Double = 0
    @Query(sort: \Expense.date, order: .reverse) private var records: [Expense]

    @State private var period: Period
    @State private var offset: Int
    @State private var selected: String?
    @State private var openPerson: String?
    @State private var selectedDay: Date?
    @State private var shown = false
    @State private var advice: String?
    @State private var adviceBusy = false
    @State private var editing: Expense?

    init(items: [SpendItem], isDemo: Bool, period: Period = .week, offset: Int = 0,
         selected: String? = nil, selectedDay: Date? = nil) {
        self.items = items
        self.isDemo = isDemo
        _period = State(initialValue: period)
        _offset = State(initialValue: offset)
        _selected = State(initialValue: selected)
        _selectedDay = State(initialValue: selectedDay)
    }

    var body: some View {
        let main = items.filter { $0.currency == currency }
        let iv = Stats.interval(period, offset: offset)
        let current = Stats.filter(main, iv)
        let previous = Stats.filter(main, Stats.interval(period, offset: offset - 1))
        let total = Stats.total(current)
        let ptotal = Stats.total(previous)
        let cats = Stats.slices(current, detailed: false)
        var prevByCat: [String: Double] = [:]
        for s in Stats.slices(previous, detailed: false) { prevByCat[s.id, default: 0] += s.amount }

        return ScrollView {
            VStack(spacing: 12) {
                ScreenTitle(eyebrow: "Аналитика", title: "Куда ушли деньги")

                if isDemo { DemoBanner() }

                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                periodNav

                summaryBlock(total: total, ptotal: ptotal, count: current.count, iv: iv)

                categoryCard(cats: cats, total: total, prevByCat: prevByCat, ptotal: ptotal, current: current)

                peopleCard(current: current, previous: previous, total: total)

                if period != .day {
                    daysCard(Stats.daily(main, iv))
                }

                insightsCard(current: current, previous: previous)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .onAppear { replay() }
        .onChange(of: period) { _, _ in offset = 0; resetSelection(); replay() }
        .onChange(of: offset) { _, _ in resetSelection(); replay() }
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    // MARK: header

    private var periodNav: some View {
        HStack {
            navButton("chevron.left") { offset -= 1 }
            Spacer()
            Text(Stats.label(period, offset: offset))
                .font(.headline)
                .foregroundStyle(Color.ink)
            Spacer()
            navButton("chevron.right") { if offset < 0 { offset += 1 } }
                .disabled(offset >= 0)
                .opacity(offset >= 0 ? 0.3 : 1)
        }
        .padding(.top, 2)
    }

    private func navButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 38, height: 38)
                .background(Color.surface, in: Circle())
                .overlay(Circle().strokeBorder(Color.line))
        }
        .buttonStyle(PressScale())
    }

    private func summaryBlock(total: Double, ptotal: Double, count: Int, iv: DateInterval) -> some View {
        VStack(spacing: 8) {
            Text(Money.signed(-total, currency))
                .font(.system(size: 40, weight: .semibold))
                .fontWidth(.expanded)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if ptotal > 0 && total > 0 {
                let ch = (total - ptotal) / ptotal
                let flat = abs(ch) < 0.03
                Text(flat ? "примерно как по \(period.prevPhrase)" : "\(ch > 0 ? "↑" : "↓") на \(Int((abs(ch) * 100).rounded()))% \(ch > 0 ? "больше" : "меньше"), чем по \(period.prevPhrase)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(flat ? Color.muted : (ch > 0 ? Color.bad : Color.good))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.surface, in: Capsule())
            }

            Group {
                if count == 0 {
                    Text("В этом периоде трат нет")
                } else {
                    let days = Double(Stats.elapsedDays(iv))
                    Text(purchases(count) + (period == .day ? "" : " · \(Money.format(total / days, currency)) в день"))
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: categories

    private func categoryCard(cats: [Slice], total: Double, prevByCat: [String: Double], ptotal: Double, current: [SpendItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "По категориям")

            ZStack {
                Donut(slices: cats, selected: selected, shown: shown)
                    .frame(width: 210, height: 210)
                VStack(spacing: 2) {
                    let sel = selected.flatMap { s in cats.first { $0.id == s } }
                    let selAmount = sel?.amount ?? total
                    Text(Money.format(selAmount, currency))
                        .font(.system(size: 19, weight: .semibold))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(sel.map { s in "\(total > 0 ? Int((selAmount / total * 100).rounded()) : 0)% · \(s.name)" } ?? "всего")
                        .font(.caption)
                        .foregroundStyle(Color.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 130)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            if cats.isEmpty {
                Text("Здесь появятся категории, как только будут траты.")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
            }

            VStack(spacing: 4) {
                ForEach(cats) { c in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                selected = selected == c.id ? nil : c.id
                            }
                        } label: {
                            SliceRow(slice: c, total: total, maxAmount: cats.first?.amount ?? 1,
                                     previous: prevByCat[c.id], hasPrevious: ptotal > 0, period: period,
                                     currency: currency, selected: selected == c.id, shown: shown)
                        }
                        .buttonStyle(.plain)

                        if selected == c.id {
                            groupDetail(current.filter { $0.category == c.group })
                                .transition(.opacity)
                        }
                    }
                }
            }
        }
        .card()
    }

    /// Subcategories as quiet lines, then the purchases
    private func groupDetail(_ inside: [SpendItem]) -> some View {
        let subs = Stats.slices(inside, detailed: true)
        let showSubs = subs.count > 1 || subs.first.map { !$0.sub.isEmpty } == true
        return VStack(alignment: .leading, spacing: 0) {
            if showSubs {
                VStack(spacing: 8) {
                    ForEach(subs) { s in
                        HStack {
                            Circle().fill(s.color).frame(width: 7, height: 7)
                            Text(s.sub.isEmpty ? "Без уточнения" : s.sub)
                                .font(.subheadline)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text(Money.format(s.amount, currency))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Color.muted)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                Rectangle().fill(Color.line).frame(height: 1).padding(.horizontal, 8)
            }
            ForEach(inside.sorted { $0.date > $1.date }) { item in
                Button { open(item) } label: { ExpenseRow(item: item) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 8)
    }

    // MARK: together

    @ViewBuilder
    private func peopleCard(current: [SpendItem], previous: [SpendItem], total: Double) -> some View {
        let people = Stats.people(current)
        if !people.isEmpty {
            let prevList = Stats.people(previous)
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Вместе")
                ForEach(people) { p in
                    let isOpen = openPerson == p.name
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { openPerson = isOpen ? nil : p.name }
                        } label: {
                            PersonRow(person: p, total: total, previous: prevList.first { $0.name == p.name }?.amount,
                                      period: period, currency: currency)
                        }
                        .buttonStyle(.plain)
                        if isOpen {
                            groupDetail(current.filter { $0.people.contains(p.name) })
                                .transition(.opacity)
                        }
                    }
                }
            }
            .card()
        }
    }

    // MARK: days

    private func daysCard(_ days: [DayTotal]) -> some View {
        let elapsed = days.filter { $0.date <= Date() }
        let avg = elapsed.isEmpty ? 0 : elapsed.reduce(0) { $0 + $1.total } / Double(elapsed.count)
        let peak = days.max { $0.total < $1.total }
        let tip: String = {
            if let d = selectedDay, let t = days.first(where: { RuDate.cal.isDate($0.date, inSameDayAs: d) }) {
                return "\(RuDate.dayLabel(t.date)): \(Money.format(t.total, currency))"
            }
            if let p = peak, p.total > 0 { return "пик: \(RuDate.dayLabel(p.date).lowercased()), \(Money.format(p.total, currency))" }
            return ""
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "По дням")
                Spacer()
                Text(tip).font(.caption).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            DayBars(days: days, period: period, average: avg, currency: currency, shown: shown, selected: $selectedDay)
                .frame(height: 170)
            Text("Нажми на столбик, чтобы увидеть сумму за день")
                .font(.caption2)
                .foregroundStyle(Color.faint)
        }
        .card()
    }

    // MARK: insights

    private func insightsCard(current: [SpendItem], previous: [SpendItem]) -> some View {
        let list = Stats.insights(period: period, offset: offset, current: current, previous: previous,
                                  currency: currency, budget: budget)
        let hasClaude = ClaudeService.stored != nil

        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Где сэкономить и что в норме")

            ForEach(list) { ins in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: ins.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ins.color)
                        .frame(width: 30, height: 30)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(Self.markdown(ins.text))
                        .font(.subheadline)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !current.isEmpty && hasClaude {
                Button { Task { await askClaude(current: current, previous: previous) } } label: {
                    HStack(spacing: 8) {
                        if adviceBusy { ProgressView().tint(Color.surface) } else { Image(systemName: "sparkles") }
                        Text(adviceBusy ? "Claude смотрит на цифры…" : "Разбор от Claude")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.surface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressScale())
                .disabled(adviceBusy)
            }

            if let advice {
                Text(advice)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    /// Bold parts without treating the text as a localization key
    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    // MARK: actions

    private func askClaude(current: [SpendItem], previous: [SpendItem]) async {
        guard let claude = ClaudeService.stored else { return }
        adviceBusy = true
        let summary = Stats.summary(period: period, offset: offset, current: current, previous: previous,
                                    currency: currency, budget: budget)
        do {
            let text = try await claude.advice(summary)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { advice = text }
        } catch {
            advice = error.localizedDescription
        }
        adviceBusy = false
    }

    private func resetSelection() {
        selected = nil
        openPerson = nil
        selectedDay = nil
        advice = nil
    }

    private func replay() {
        shown = false
        withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.05)) { shown = true }
    }

    private func open(_ item: SpendItem) {
        if isDemo {
            app.showToast("Это пример. Запиши свою трату, и пример исчезнет.")
            return
        }
        editing = records.first { $0.uid.uuidString == item.id }
    }
}

// MARK: - Light hand-drawn charts (no gestures inside, nothing to crash)

struct Donut: View {
    let slices: [Slice]
    let selected: String?
    let shown: Bool

    private struct Arc: Identifiable {
        let slice: Slice
        let from: Double
        let to: Double
        var id: String { slice.id }
    }

    private var arcs: [Arc] {
        let total = slices.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        let gap = slices.count > 1 ? 0.006 : 0
        var start = 0.0
        var out: [Arc] = []
        for s in slices {
            let end = start + s.amount / total
            let from = min(start + gap / 2, end)
            out.append(Arc(slice: s, from: from, to: max(from, end - gap / 2)))
            start = end
        }
        return out
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.surface2, lineWidth: 20)
            ForEach(arcs) { arc in
                Circle()
                    .trim(from: arc.from, to: shown ? arc.to : arc.from)
                    .stroke(arc.slice.color, style: StrokeStyle(lineWidth: selected == arc.id ? 28 : 20, lineCap: .butt))
                    .opacity(selected == nil || selected == arc.id ? 1 : 0.3)
                    .animation(.spring(response: 0.9, dampingFraction: 0.85), value: shown)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(14)
    }
}

struct DayBars: View {
    let days: [DayTotal]
    let period: Period
    let average: Double
    let currency: String
    let shown: Bool
    @Binding var selected: Date?

    var body: some View {
        let maxValue = max(days.map(\.total).max() ?? 0, 1)
        GeometryReader { geo in
            let labelH: CGFloat = 16
            let h = max(1, geo.size.height - labelH - 4)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: days.count > 10 ? 2 : 8) {
                    ForEach(days) { d in
                        let isSel = selected.map { RuDate.cal.isDate($0, inSameDayAs: d.date) } ?? false
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(d.isToday ? Color.warm : Color.ink.opacity(isSel ? 0.55 : 0.18))
                                .frame(height: max(2, h * CGFloat(shown ? d.total / maxValue : 0)))
                            Text(label(d))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.muted)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(height: labelH)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = isSel ? nil : d.date }
                    }
                }
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: shown)

                if average > 0 {
                    let y = h - h * CGFloat(min(1, average / maxValue))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.muted, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .allowsHitTesting(false)
                    Text("среднее \(Money.format(average, currency))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.muted)
                        .padding(.horizontal, 4)
                        .background(Color.surface)
                        .offset(x: max(0, geo.size.width - 150), y: max(0, y - 16))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func label(_ d: DayTotal) -> String {
        let p = RuDate.parts(d.date)
        if period == .week { return RuDate.weekdaysShort[p.weekday] }
        return (p.day == 1 || p.day % 5 == 0 || d.isToday) ? "\(p.day)" : ""
    }
}

struct SliceRow: View {
    let slice: Slice
    let total: Double
    let maxAmount: Double
    let previous: Double?
    let hasPrevious: Bool
    let period: Period
    let currency: String
    let selected: Bool
    let shown: Bool

    var body: some View {
        let share = total > 0 ? Int((slice.amount / total * 100).rounded()) : 0

        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ItemIcon(symbol: slice.group.symbol, color: slice.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slice.name).font(.body.weight(.medium)).foregroundStyle(Color.ink).lineLimit(1)
                    Text("\(purchases(slice.count)) · \(share)%").font(.caption).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.format(slice.amount, currency)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Color.ink)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface2)
                    Capsule().fill(slice.color)
                        .frame(width: geo.size.width * CGFloat(shown ? slice.amount / max(maxAmount, 0.01) : 0))
                }
            }
            .frame(height: 5)
            .padding(.leading, 54)
        }
        .padding(8)
        .background(selected ? Color.surface2.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    /// "↑ 505 ₽ к прошлой неделе" instead of a bare "+505"
    static func delta(_ amount: Double, previous: Double?, hasPrevious: Bool, period: Period, currency: String) -> (String, Color) {
        if let p = previous, p > 0 {
            let diff = amount - p
            if abs(diff) < max(1, p * 0.05) { return ("как по \(period.prevPhrase)", Color.faint) }
            return ("\(diff > 0 ? "↑" : "↓") \(Money.format(abs(diff), currency)) к \(period.prevPhrase)", diff > 0 ? Color.bad : Color.good)
        }
        return hasPrevious ? ("раньше не было", Color.faint) : ("", Color.faint)
    }
}

struct PersonRow: View {
    let person: PersonTotal
    let total: Double
    let previous: Double?
    let period: Period
    let currency: String

    var body: some View {
        let share = total > 0 ? Int((person.amount / total * 100).rounded()) : 0
        HStack(spacing: 12) {
            ItemIcon(symbol: "heart.fill", color: Color(hue: 0.95, saturation: 0.45, brightness: 0.88))
            VStack(alignment: .leading, spacing: 2) {
                Text(person.withName).font(.body.weight(.medium)).foregroundStyle(Color.ink)
                Text("\(purchases(person.count)) · \(share)% всех трат").font(.caption).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(person.amount, currency)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Color.ink)
            }
        }
        .padding(8)
        .contentShape(Rectangle())
    }
}
