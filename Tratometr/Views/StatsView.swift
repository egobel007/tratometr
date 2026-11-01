import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @EnvironmentObject private var app: AppState
    let items: [SpendItem]
    let isDemo: Bool

    @AppStorage("currency") private var currency = "RUB"
    @AppStorage("budget") private var budget: Double = 0
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var period: Period = .week
    @State private var offset = 0
    @AppStorage("stats_detailed") private var detailed = false
    @State private var selected: String?
    @State private var openPerson: String?
    @State private var angle: Double?
    @State private var selectedDay: Date?
    @State private var shown = false
    @State private var advice: String?
    @State private var adviceBusy = false
    @State private var editing: Expense?

    var body: some View {
        let main = items.filter { $0.currency == currency }
        let iv = Stats.interval(period, offset: offset)
        let current = Stats.filter(main, iv)
        let previous = Stats.filter(main, Stats.interval(period, offset: offset - 1))
        let total = Stats.total(current)
        let ptotal = Stats.total(previous)
        let cats = Stats.slices(current, detailed: detailed)
        let prevByCat = Dictionary(uniqueKeysWithValues: Stats.slices(previous, detailed: detailed).map { ($0.id, $0.amount) })
        let otherCurrency = Stats.filter(items, iv).filter { $0.currency != currency }.count

        ScrollView {
            VStack(spacing: 12) {
                ScreenTitle(eyebrow: "Аналитика", title: "Куда ушли деньги")

                if isDemo { DemoBanner() }

                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                periodNav

                summaryBlock(total: total, ptotal: ptotal, count: current.count, iv: iv, otherCurrency: otherCurrency)

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
        .onChange(of: detailed) { _, _ in selected = nil; angle = nil; replay() }
        .onChange(of: angle) { _, a in
            guard let a else { return }
            var acc = 0.0
            for c in cats {
                acc += c.amount
                if a <= acc {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selected = c.id }
                    break
                }
            }
        }
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    // MARK: header pieces

    private var periodNav: some View {
        HStack {
            navButton("chevron.left") { offset -= 1 }
            Spacer()
            Text(Stats.label(period, offset: offset))
                .font(.headline)
                .foregroundStyle(Color.ink)
                .contentTransition(.opacity)
            Spacer()
            navButton("chevron.right") { offset += 1 }
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

    private func summaryBlock(total: Double, ptotal: Double, count: Int, iv: DateInterval, otherCurrency: Int) -> some View {
        VStack(spacing: 8) {
            Text(Money.format(total, currency))
                .font(.system(size: 40, weight: .semibold))
                .fontWidth(.expanded)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: total))
                .animation(.snappy, value: total)

            if ptotal > 0 && total > 0 {
                let ch = (total - ptotal) / ptotal
                let flat = abs(ch) < 0.03
                let color: Color = flat ? .muted : (ch > 0 ? .bad : .good)
                Text(flat ? "примерно как по \(period.prevPhrase)" : "\(ch > 0 ? "↑" : "↓") \(Int((abs(ch) * 100).rounded()))% к \(period.prevPhrase)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.surface, in: Capsule())
            }

            Group {
                if count == 0 {
                    Text("В этом периоде трат нет")
                } else {
                    let days = Double(Stats.elapsedDays(iv))
                    let perDay = period == .day ? "" : " · \(Money.format(total / days, currency)) в день"
                    let other = otherCurrency > 0 ? " · ещё \(otherCurrency) в другой валюте" : ""
                    Text(purchases(count) + perDay + other)
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
            HStack {
                Text("По категориям").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Color.ink)
                Spacer()
                Picker("Вид", selection: $detailed) {
                    Text("Группы").tag(false)
                    Text("Подробно").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            ZStack {
                if cats.isEmpty {
                    Circle().stroke(Color.surface2, lineWidth: 22).padding(11)
                } else {
                    Chart(cats) { c in
                        SectorMark(angle: .value("Сумма", c.amount),
                                   innerRadius: .ratio(0.64),
                                   outerRadius: .ratio(selected == c.id ? 1.0 : 0.94),
                                   angularInset: 1.5)
                            .cornerRadius(5)
                            .foregroundStyle(c.color)
                            .opacity(selected == nil || selected == c.id ? 1 : 0.28)
                    }
                    .chartLegend(.hidden)
                    .chartAngleSelection(value: $angle)
                }
                VStack(spacing: 2) {
                    let sel = selected.flatMap { s in cats.first { $0.id == s } }
                    let selAmount = sel?.amount ?? total
                    Text(Money.format(selAmount, currency))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: selAmount))
                    Text(sel.map { s in "\(total > 0 ? Int((selAmount / total * 100).rounded()) : 0)% · \(s.name)" } ?? "всего")
                        .font(.caption)
                        .foregroundStyle(Color.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 130)
            }
            .frame(height: 230)
            .frame(maxWidth: .infinity)
            .rotation3DEffect(.degrees(shown ? 0 : 62), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotationEffect(.degrees(shown ? 0 : -50))
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)

            if cats.isEmpty {
                Text("Здесь появятся категории, как только будут траты.")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
            } else {
                Text(detailed ? "Каждая подкатегория отдельно. Нажми, чтобы увидеть покупки." : "Нажми на группу, чтобы увидеть подкатегории и покупки.")
                    .font(.caption)
                    .foregroundStyle(Color.faint)
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
                                     previous: prevByCat[c.id], hasPrevious: ptotal > 0,
                                     currency: currency, selected: selected == c.id, shown: shown)
                        }
                        .buttonStyle(.plain)

                        if selected == c.id {
                            let inside = current.filter { $0.category == c.group && (!detailed || $0.sub == c.sub) }
                            VStack(alignment: .leading, spacing: 0) {
                                if !detailed {
                                    let subs = Stats.slices(inside, detailed: true)
                                    if subs.count > 1 || subs.first.map({ !$0.sub.isEmpty }) == true {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(subs) { sl in
                                                    Chip(title: "\(sl.sub.isEmpty ? "Без уточнения" : sl.sub) · \(Money.format(sl.amount, currency))",
                                                         color: sl.color)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                                ForEach(inside.sorted { $0.date > $1.date }) { item in
                                    Button { open(item) } label: { ExpenseRow(item: item) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
        .card()
    }

    // MARK: people

    @ViewBuilder
    private func peopleCard(current: [SpendItem], previous: [SpendItem], total: Double) -> some View {
        let people = Stats.people(current)
        let prev = Dictionary(uniqueKeysWithValues: Stats.people(previous).map { ($0.name, $0.amount) })
        let known = TagStore.shared.people
        if !people.isEmpty || !known.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").foregroundStyle(Color.bubble)
                    Text("Вместе").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Color.ink)
                    Spacer()
                }
                if people.isEmpty {
                    let with = known.first.map { "с " + Tags.instrumental($0.name) } ?? "с Ариной"
                    Text("В этом периоде нет трат с отметкой. Скажи, например: «кафе " + with + " 3200», и здесь будет видно, сколько уходит на вас.")
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(people) { p in
                    let items = current.filter { $0.people.contains(p.name) }
                    let isOpen = openPerson == p.name
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { openPerson = isOpen ? nil : p.name }
                        } label: {
                            PersonRow(person: p, total: total, previous: prev[p.name], currency: currency, shown: shown)
                        }
                        .buttonStyle(.plain)

                        if isOpen {
                            let groups = Stats.slices(items, detailed: detailed)
                            VStack(spacing: 6) {
                                ForEach(groups) { g in
                                    HStack(spacing: 10) {
                                        ItemIcon(symbol: g.group.symbol, color: g.color, size: 28)
                                        Text(g.name).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink).lineLimit(1)
                                        Spacer()
                                        Text(Money.format(g.amount, currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                            .foregroundStyle(Color.ink)
                                    }
                                }
                            }
                            .padding(.leading, 8)
                            VStack(spacing: 0) {
                                ForEach(items.sorted { $0.date > $1.date }.prefix(15)) { item in
                                    Button { open(item) } label: { ExpenseRow(item: item) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
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
        let labelFormat: Date.FormatStyle = period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day()
        let tip: String = {
            if let d = selectedDay, let t = days.first(where: { RuDate.cal.isDate($0.date, inSameDayAs: d) }) {
                return "\(RuDate.dayLabel(t.date)): \(Money.format(t.total, currency))"
            }
            if let p = peak, p.total > 0 { return "пик: \(RuDate.dayLabel(p.date).lowercased()), \(Money.format(p.total, currency))" }
            return ""
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("По дням").font(.subheadline.weight(.semibold)).foregroundStyle(Color.muted)
                Spacer()
                Text(tip).font(.caption).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Chart {
                ForEach(days) { d in
                    BarMark(x: .value("День", d.date, unit: .day),
                            y: .value("Сумма", shown ? d.total : 0),
                            width: .ratio(0.62))
                        .cornerRadius(4)
                        .foregroundStyle(d.isToday ? Color.bubble : Color.violet.opacity(isSelected(d) ? 0.75 : 0.35))
                }
                if avg > 0 {
                    RuleMark(y: .value("Среднее", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(Color.muted)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("среднее \(Money.format(avg, currency))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.muted)
                        }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: labelFormat, centered: true)
                }
            }
            .chartXSelection(value: $selectedDay)
            .frame(height: 170)
        }
        .card()
    }

    private func isSelected(_ d: DayTotal) -> Bool {
        guard let s = selectedDay else { return false }
        return RuDate.cal.isDate(d.date, inSameDayAs: s)
    }

    // MARK: insights

    private func insightsCard(current: [SpendItem], previous: [SpendItem]) -> some View {
        let list = Stats.insights(period: period, offset: offset, current: current, previous: previous,
                                  currency: currency, budget: budget)
        let hasClaude = ClaudeService.stored != nil

        return VStack(alignment: .leading, spacing: 14) {
            Text("Где сэкономить и что в норме").font(.subheadline.weight(.semibold)).foregroundStyle(Color.muted)

            ForEach(list) { ins in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: ins.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ins.color)
                        .frame(width: 30, height: 30)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(LocalizedStringKey(ins.text))
                        .font(.subheadline)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !current.isEmpty {
                if hasClaude {
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
                } else {
                    Text("Добавь ключ Claude в настройках, и он даст личный разбор: где резать, а где можно не жалеть.")
                        .font(.caption)
                        .foregroundStyle(Color.faint)
                }
            }

            if let advice {
                Text(advice)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
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
        angle = nil
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
        editing = expenses.first { $0.uid.uuidString == item.id }
    }
}

struct SliceRow: View {
    let slice: Slice
    let total: Double
    let maxAmount: Double
    let previous: Double?
    let hasPrevious: Bool
    let currency: String
    let selected: Bool
    let shown: Bool

    var body: some View {
        let share = total > 0 ? Int((slice.amount / total * 100).rounded()) : 0
        let delta: (String, Color) = {
            if let p = previous, p > 0 {
                let ch = (slice.amount - p) / p
                if abs(ch) < 0.05 { return ("без изменений", Color.faint) }
                let diff = Money.format(abs(slice.amount - p), currency)
                return (ch > 0 ? "+\(diff)" : "−\(diff)", ch > 0 ? Color.bad : Color.good)
            }
            return hasPrevious ? ("новое", Color.warn) : ("", Color.faint)
        }()

        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ItemIcon(symbol: slice.group.symbol, color: slice.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slice.name).font(.body.weight(.semibold)).foregroundStyle(Color.ink).lineLimit(1)
                    Text((slice.sub.isEmpty ? "" : slice.group.name + " · ") + "\(purchases(slice.count)) · \(share)%")
                        .font(.caption).foregroundStyle(Color.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.format(slice.amount, currency)).font(.body.weight(.bold)).monospacedDigit().foregroundStyle(Color.ink)
                    if !delta.0.isEmpty { Text(delta.0).font(.caption).monospacedDigit().foregroundStyle(delta.1) }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface2)
                    Capsule().fill(slice.color.gradient)
                        .frame(width: geo.size.width * (shown ? slice.amount / max(maxAmount, 0.01) : 0))
                }
            }
            .frame(height: 6)
            .padding(.leading, 54)
        }
        .padding(8)
        .background(selected ? Color.surface2.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct PersonRow: View {
    let person: PersonTotal
    let total: Double
    let previous: Double?
    let currency: String
    let shown: Bool

    var body: some View {
        let share = total > 0 ? person.amount / total : 0
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [Color.bubble, Color.violet], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.bubble.opacity(0.35), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.withName).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                    Text("\(purchases(person.count)) · \(Int((share * 100).rounded()))% всех трат")
                        .font(.caption).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.format(person.amount, currency)).font(.body.weight(.bold)).monospacedDigit().foregroundStyle(Color.ink)
                    if let p = previous, p > 0, abs(person.amount - p) > person.amount * 0.05 {
                        let diff = person.amount - p
                        Text((diff > 0 ? "+" : "−") + Money.format(abs(diff), currency))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(diff > 0 ? Color.bad : Color.good)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface2)
                    Capsule().fill(LinearGradient(colors: [Color.bubble, Color.violet], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (shown ? share : 0))
                }
            }
            .frame(height: 6)
            .padding(.leading, 54)
        }
        .padding(8)
        .contentShape(Rectangle())
    }
}
