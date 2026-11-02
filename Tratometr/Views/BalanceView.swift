import SwiftUI
import SwiftData

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
    @State private var editing: Expense?

    var body: some View {
        let sp = spends.filter { $0.currency == currency }
        let inc = incomes.filter { $0.currency == currency }
        let earliest = (sp + inc).map(\.date).min()
        let iv = Flow.interval(period, offset: offset, earliest: earliest)
        let curIn = Stats.filter(inc, iv)
        let income = Stats.total(curIn)
        let spent = Stats.total(Stats.filter(sp, iv))
        let net = income - spent
        let months = Flow.months(period == .month ? Flow.interval(.all, offset: 0, earliest: earliest) : iv,
                                 spends: sp, incomes: inc).reversed()

        ScrollView {
            VStack(spacing: 12) {
                ScreenTitle(eyebrow: "Баланс", title: "Сколько остаётся")

                if isDemo { DemoBanner() }

                Picker("Период", selection: $period) {
                    ForEach(BalancePeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if period != .all { periodNav(earliest: earliest) }

                // the main number
                VStack(spacing: 8) {
                    Text(Money.signed(net, currency))
                        .font(.system(size: 44, weight: .semibold))
                        .fontWidth(.expanded)
                        .foregroundStyle(net >= 0 ? Color.ink : Color.bad)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: net))
                        .animation(.snappy, value: net)
                    Text(subtitle(income: income, spent: spent))
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        flow("Пришло", income, .good)
                        flow("Ушло", spent, .ink)
                    }
                    if income > 0 {
                        ThinBar(value: spent / income, color: spent > income ? Color.bad : Color.ink.opacity(0.75))
                    }
                    if period == .month && salary > 0 {
                        Rectangle().fill(Color.line).frame(height: 1)
                        salaryBlock(Stats.total(curIn.filter { $0.income == .salary }))
                    }
                }
                .card()

                if !months.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "По месяцам")
                        ForEach(Array(months)) { m in
                            HStack {
                                Text(RuDate.months[RuDate.parts(m.month).month])
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Text("+\(Money.format(m.income, currency))  −\(Money.format(m.spent, currency))")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(Money.signed(m.net, currency))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(m.net >= 0 ? Color.good : Color.bad)
                                    .frame(minWidth: 96, alignment: .trailing)
                            }
                        }
                    }
                    .card()
                }

                sourcesCard(curIn, total: income)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .onChange(of: period) { _, _ in offset = 0 }
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    // MARK: pieces

    private func subtitle(income: Double, spent: Double) -> String {
        if income == 0 && spent == 0 { return "Пока нет записей за этот период" }
        if income == 0 { return "Поступлений пока нет. Скажи, например: «пришло 40 000, часть зарплаты»" }
        let net = income - spent
        if net >= 0 { return "В плюсе. Отложено \(Int((net / income * 100).rounded()))% от поступлений" }
        return "В минусе: потрачено больше, чем пришло"
    }

    private func flow(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Color.muted)
            Text(Money.format(value, currency))
                .font(.system(size: 20, weight: .semibold))
                .fontWidth(.expanded)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func salaryBlock(_ received: Double) -> some View {
        let left = salary - received
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Зарплата").font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
                Spacer()
                Text("\(Money.format(received, currency)) из \(Money.format(salary, currency))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.muted)
            }
            ThinBar(value: received / salary, color: .good, height: 5)
            if left > 0 && offset == 0 {
                Text("Ещё ждём \(Money.format(left, currency))").font(.caption).foregroundStyle(Color.muted)
            }
        }
    }

    private func periodNav(earliest: Date?) -> some View {
        HStack {
            navButton("chevron.left") { offset -= 1 }
            Spacer()
            Text(Flow.label(period, offset: offset, earliest: earliest))
                .font(.headline)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 38, height: 38)
                .background(Color.surface, in: Circle())
                .overlay(Circle().strokeBorder(Color.line))
        }
        .buttonStyle(PressScale())
    }

    @ViewBuilder
    private func sourcesCard(_ items: [SpendItem], total: Double) -> some View {
        let groups = Dictionary(grouping: items, by: \.income)
            .map { SourceGroup(source: $0.key, items: $0.value, amount: Stats.total($0.value)) }
            .sorted { $0.amount > $1.amount }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "Откуда пришло")
                ForEach(groups) { g in
                    let subs = Flow.bySource(g.items)
                    let showSubs = subs.count > 1 || subs.first.map { !$0.sub.isEmpty } == true
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            ItemIcon(symbol: g.source.symbol, color: g.source.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.source.name).font(.body.weight(.medium)).foregroundStyle(Color.ink)
                                Text("\(g.items.count) \(plural(g.items.count, "поступление", "поступления", "поступлений")) · \(total > 0 ? Int((g.amount / total * 100).rounded()) : 0)%")
                                    .font(.caption)
                                    .foregroundStyle(Color.muted)
                            }
                            Spacer()
                            Text("+" + Money.format(g.amount, currency))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.good)
                        }
                        if showSubs {
                            VStack(spacing: 6) {
                                ForEach(subs) { s in
                                    HStack {
                                        Circle().fill(g.source.color).frame(width: 6, height: 6)
                                        Text(s.sub.isEmpty ? "Без уточнения" : s.sub)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.ink)
                                        Spacer()
                                        Text("+" + Money.format(s.amount, currency))
                                            .font(.subheadline)
                                            .monospacedDigit()
                                            .foregroundStyle(Color.muted)
                                    }
                                }
                            }
                            .padding(.leading, 54)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Rectangle().fill(Color.line).frame(height: 1).padding(.vertical, 4)
                ForEach(items.sorted { $0.date > $1.date }.prefix(12)) { item in
                    Button { open(item) } label: { ExpenseRow(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    private func open(_ item: SpendItem) {
        if isDemo {
            app.showToast("Это пример. Запиши своё поступление, и пример исчезнет.")
            return
        }
        editing = records.first { $0.uid.uuidString == item.id }
    }
}

struct SourceGroup: Identifiable {
    let source: IncomeSource
    let items: [SpendItem]
    let amount: Double
    var id: String { source.rawValue }
}
