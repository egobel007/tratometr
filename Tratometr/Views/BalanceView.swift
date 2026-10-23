import SwiftUI
import SwiftData
import Charts

/// Money in vs money out: how much stays, month by month and overall.
struct BalanceView: View {
    @EnvironmentObject private var app: AppState
    let spends: [SpendItem]
    let incomes: [SpendItem]
    let isDemo: Bool

    @AppStorage("currency") private var currency = "RUB"
    @AppStorage("salary") private var salary: Double = 0
    @Query(sort: \Expense.date, order: .reverse) private var records: [Expense]

    @State private var period: BalancePeriod = .month
    @State private var offset = 0
    @State private var shown = false
    @State private var editing: Expense?

    var body: some View {
        let sp = spends.filter { $0.currency == currency }
        let inc = incomes.filter { $0.currency == currency }
        let earliest = (sp + inc).map(\.date).min()
        let iv = Flow.interval(period, offset: offset, earliest: earliest)
        let curIn = Stats.filter(inc, iv)
        let curOut = Stats.filter(sp, iv)
        let income = Stats.total(curIn)
        let spent = Stats.total(curOut)
        let allIv = Flow.interval(.all, offset: 0, earliest: earliest)
        let allMonths = Flow.months(allIv, spends: sp, incomes: inc)
        let chartMonths: [MonthFlow] = {
            switch period {
            case .year: return Flow.months(iv, spends: sp, incomes: inc)
            default:
                // the selected month and up to 5 months before it
                let end = period == .month ? iv.end : allIv.end
                let start = RuDate.cal.date(byAdding: .month, value: -6, to: end)!
                return Flow.months(DateInterval(start: max(start, allIv.start), end: end), spends: sp, incomes: inc)
            }
        }()

        ScrollView {
            VStack(spacing: 12) {
                ScreenTitle(eyebrow: "Баланс", title: "Сколько остаётся")

                if isDemo { DemoBanner() }

                Picker("Период", selection: $period) {
                    ForEach(BalancePeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if period != .all { periodNav(earliest: earliest) }

                NetCard(label: Flow.label(period, offset: offset, earliest: earliest),
                        income: income, spent: spent, currency: currency, shown: shown)

                if period == .month {
                    SalaryCard(received: Stats.total(curIn.filter { $0.income == .salary }),
                               expected: salary, currency: currency, isCurrent: offset == 0)
                }

                monthsCard(chartMonths)

                totalCard(allMonths)

                sourcesCard(curIn, total: income)

                incomesList(curIn)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: replay)
        .onChange(of: period) { _, _ in offset = 0; replay() }
        .onChange(of: offset) { _, _ in replay() }
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    // MARK: pieces

    private func periodNav(earliest: Date?) -> some View {
        HStack {
            navButton("chevron.left") { offset -= 1 }
            Spacer()
            Text(Flow.label(period, offset: offset, earliest: earliest))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
            Spacer()
            navButton("chevron.right") { offset += 1 }
                .disabled(offset >= 0)
                .opacity(offset >= 0 ? 0.3 : 1)
        }
    }

    private func navButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.violet)
                .frame(width: 38, height: 38)
                .background(Color.surface, in: Circle())
                .shadow(color: Color.violet.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(PressScale())
    }

    private func monthsCard(_ months: [MonthFlow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("По месяцам")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)

            if months.isEmpty {
                Text("Здесь появятся месяцы, когда будут записи.")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
            } else {
                Chart {
                    ForEach(months) { m in
                        BarMark(x: .value("Месяц", m.month, unit: .month),
                                y: .value("Сумма", shown ? m.income : 0))
                            .foregroundStyle(by: .value("Тип", "Пришло"))
                            .position(by: .value("Тип", "Пришло"))
                            .cornerRadius(5)
                        BarMark(x: .value("Месяц", m.month, unit: .month),
                                y: .value("Сумма", shown ? m.spent : 0))
                            .foregroundStyle(by: .value("Тип", "Ушло"))
                            .position(by: .value("Тип", "Ушло"))
                            .cornerRadius(5)
                    }
                }
                .chartForegroundStyleScale(["Пришло": Color.good, "Ушло": Color.warm])
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text(RuDate.monthsShortNom[RuDate.parts(d).month])
                            }
                        }
                    }
                }
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 180)

                VStack(spacing: 6) {
                    ForEach(months.reversed()) { m in
                        HStack {
                            Text(RuDate.months[RuDate.parts(m.month).month])
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text("+\(Money.format(m.income, currency))  −\(Money.format(m.spent, currency))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Color.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(Money.signed(m.net, currency))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(m.net >= 0 ? Color.good : Color.bad)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background((m.net >= 0 ? Color.good : Color.bad).opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
        .card()
    }

    private func totalCard(_ months: [MonthFlow]) -> some View {
        var acc = 0.0
        let points: [CumPoint] = months.map { m in acc += m.net; return CumPoint(date: m.month, value: acc) }
        let total = acc
        let plusMonths = months.filter { $0.net >= 0 }.count

        return VStack(alignment: .leading, spacing: 10) {
            Text("Общая картина")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
            HStack(alignment: .firstTextBaseline) {
                Text(Money.signed(total, currency))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(total >= 0 ? Color.good : Color.bad)
                    .contentTransition(.numericText(value: total))
                Spacer()
                if !months.isEmpty {
                    Text("в плюсе \(plusMonths) из \(months.count) \(plural(months.count, "месяца", "месяцев", "месяцев"))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.muted)
                }
            }
            Text(total >= 0 ? "Столько удалось отложить за всё время, что ты ведёшь учёт." : "Столько за всё время ушло сверх поступлений.")
                .font(.footnote)
                .foregroundStyle(Color.muted)

            if points.count > 1 {
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Месяц", p.date, unit: .month), y: .value("Накоплено", shown ? p.value : 0))
                            .foregroundStyle(LinearGradient(colors: [Color.mintPop.opacity(0.45), Color.sky.opacity(0.05)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Месяц", p.date, unit: .month), y: .value("Накоплено", shown ? p.value : 0))
                            .foregroundStyle(Palette.plus)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Месяц", p.date, unit: .month), y: .value("Накоплено", shown ? p.value : 0))
                            .foregroundStyle(Color.mintPop)
                            .symbolSize(40)
                    }
                    RuleMark(y: .value("Ноль", 0))
                        .foregroundStyle(Color.faint.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text(RuDate.monthsShortNom[RuDate.parts(d).month])
                            }
                        }
                    }
                }
                .frame(height: 140)
            }
        }
        .card()
    }

    private func sourcesCard(_ items: [SpendItem], total: Double) -> some View {
        let sources = Flow.bySource(items)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Откуда пришло")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
            if sources.isEmpty {
                Text("Поступлений в этом периоде нет. Скажи, например: «пришло 40 000, часть зарплаты».")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                Button { app.compose = .income } label: {
                    Label("Добавить поступление", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Palette.plus, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressScale())
            } else {
                ForEach(sources) { s in
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            ItemIcon(symbol: s.source.symbol, color: s.source.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.source.name).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                                Text("\(s.count) \(plural(s.count, "поступление", "поступления", "поступлений")) · \(total > 0 ? Int((s.amount / total * 100).rounded()) : 0)%")
                                    .font(.caption)
                                    .foregroundStyle(Color.muted)
                            }
                            Spacer()
                            Text("+" + Money.format(s.amount, currency))
                                .font(.body.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.good)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.surface2)
                                Capsule().fill(s.source.color.gradient)
                                    .frame(width: geo.size.width * (shown && total > 0 ? s.amount / total : 0))
                            }
                        }
                        .frame(height: 6)
                        .padding(.leading, 54)
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func incomesList(_ items: [SpendItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Поступления")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                ForEach(items.sorted { $0.date > $1.date }.prefix(20)) { item in
                    Button { open(item) } label: { ExpenseRow(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    private func replay() {
        shown = false
        withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.05)) { shown = true }
    }

    private func open(_ item: SpendItem) {
        if isDemo {
            app.showToast("Это пример. Запиши своё поступление, и пример исчезнет.")
            return
        }
        editing = records.first { $0.uid.uuidString == item.id }
    }
}

struct CumPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

// MARK: - Big "how much is left" card

struct NetCard: View {
    let label: String
    let income: Double
    let spent: Double
    let currency: String
    let shown: Bool

    var body: some View {
        let net = income - spent
        let plus = net >= 0
        let rate = income > 0 ? Int((net / income * 100).rounded()) : 0
        let spentShare = income > 0 ? min(1, spent / income) : (spent > 0 ? 1 : 0)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Остаток · \(label)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                Image(systemName: plus ? "party.popper.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Color.white.opacity(0.92))

            Text(Money.signed(net, currency))
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: net))
                .animation(.snappy, value: net)

            Text(subtitle(net: net, rate: rate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.28))
                    Capsule().fill(Color.white).frame(width: geo.size.width * (shown ? spentShare : 0))
                }
            }
            .frame(height: 8)

            HStack(spacing: 8) {
                flowBox("Пришло", income, "arrow.down.circle.fill")
                flowBox("Ушло", spent, "arrow.up.circle.fill")
            }
        }
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(plus ? Palette.plus : Palette.minus)
                Circle().fill(Color.white.opacity(0.16)).frame(width: 170).offset(x: 150, y: -80)
                Circle().fill(Color.white.opacity(0.10)).frame(width: 120).offset(x: -150, y: 90)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .shadow(color: (plus ? Color.mintPop : Color.coral).opacity(0.35), radius: 22, y: 12)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: plus)
    }

    private func subtitle(net: Double, rate: Int) -> String {
        if income == 0 && spent == 0 { return "Пока нет записей за этот период." }
        if income == 0 { return "Поступлений пока нет. Добавь зарплату, чтобы увидеть остаток." }
        if net >= 0 { return "Ты в плюсе! Отложено \(rate)% от поступлений." }
        return "Ушёл в минус: потрачено больше, чем пришло."
    }

    private func flowBox(_ title: String, _ value: Double, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).opacity(0.85)
                Text(Money.format(value, currency))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Salary that arrives in parts

struct SalaryCard: View {
    @EnvironmentObject private var app: AppState
    let received: Double
    let expected: Double
    let currency: String
    let isCurrent: Bool
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ItemIcon(symbol: IncomeSource.salary.symbol, color: IncomeSource.salary.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Зарплата за месяц")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
            }
            if expected > 0 {
                let pct = min(1, received / expected)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.surface2)
                        Capsule().fill(Palette.plus).frame(width: geo.size.width * (shown ? pct : 0))
                    }
                }
                .frame(height: 10)
                HStack {
                    Text("Пришло \(Money.format(received, currency))")
                    Spacer()
                    Text("из \(Money.format(expected, currency))")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.muted)
            } else {
                Button { app.showSettings = true } label: {
                    Label("Указать зарплату в настройках", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.violet)
                }
            }
        }
        .card()
        .onAppear { withAnimation(.spring(response: 1, dampingFraction: 0.85).delay(0.2)) { shown = true } }
    }

    private var detail: String {
        guard expected > 0 else {
            return received > 0 ? "Пришло \(Money.format(received, currency)). Укажи сумму зарплаты, и я покажу, сколько ещё ждать." : "Укажи сумму зарплаты, и я покажу, сколько уже пришло и сколько ещё ждать."
        }
        let left = expected - received
        if left <= 0 { return "Вся зарплата пришла" + (left < 0 ? ", даже больше на \(Money.format(-left, currency))" : "") }
        return isCurrent ? "Ещё ждём \(Money.format(left, currency))" : "Не хватило до полной \(Money.format(left, currency))"
    }
}
