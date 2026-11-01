import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    let spends: [SpendItem]
    let incomes: [SpendItem]
    let isDemo: Bool

    @AppStorage("currency") private var currency = "RUB"
    @AppStorage("budget") private var budget: Double = 0
    @Query(sort: \Expense.date, order: .reverse) private var records: [Expense]
    @State private var editing: Expense?
    @State private var orbTaps = 0

    var body: some View {
        let main = spends.filter { $0.currency == currency }
        let mainIn = incomes.filter { $0.currency == currency }
        let todayItems = Stats.filter(main, Stats.interval(.day, offset: 0))
        let monthIv = Stats.interval(.month, offset: 0)
        let week = Stats.total(Stats.filter(main, Stats.interval(.week, offset: 0)))
        let month = Stats.total(Stats.filter(main, monthIv))
        let monthIn = Stats.total(Stats.filter(mainIn, monthIv))
        let dayOfMonth = Double(RuDate.cal.component(.day, from: Date()))
        let recent = (spends + incomes).sorted { $0.date > $1.date }.prefix(6)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(eyebrow: RuDate.headerToday(), title: "Тратометр", showSettings: true)

                if isDemo { DemoBanner().padding(.bottom, 12).riseIn(0) }

                HeroCard(today: Stats.total(todayItems), count: todayItems.count, week: week, month: month,
                         average: month / dayOfMonth, monthIncome: monthIn, budget: budget,
                         currency: currency, motion: app.motion)
                    .onTapGesture { if monthIn > 0 { app.go(.balance) } }
                    .riseIn(0.02)

                orbBlock.riseIn(0.1)

                HStack {
                    Text("Последние").font(.headline).fontWidth(.expanded).foregroundStyle(Color.ink)
                    Spacer()
                    Button("Все") { app.go(.history) }
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                }
                .padding(.top, 18)
                .padding(.bottom, 4)
                .riseIn(0.16)

                VStack(spacing: 0) {
                    ForEach(Array(recent)) { item in
                        Button { open(item) } label: { ExpenseRow(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .riseIn(0.2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    private var caption: String {
        switch app.mood {
        case .idle: return "Нажми на шар и скажи, на что потратил"
        case .listen: return "Слушаю…"
        case .think: return "Записываю…"
        }
    }

    private var orbBlock: some View {
        VStack(spacing: 6) {
            OrbView(engine: app.orb, paused: app.tab != .home || app.compose != nil)
                .frame(width: 280, height: 280)
                .contentShape(Circle())
                .onTapGesture {
                    orbTaps += 1
                    app.compose = .voice
                }
                .sensoryFeedback(.impact(weight: .light), trigger: orbTaps)
                .accessibilityElement()
                .accessibilityLabel("Записать голосом")
                .accessibilityAddTraits(.isButton)

            Text(caption)
                .font(.subheadline)
                .foregroundStyle(Color.muted)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: app.mood)

            HStack(spacing: 8) {
                Menu {
                    Button { app.compose = .scan } label: { Label("Сфотографировать чек", systemImage: "doc.viewfinder") }
                    Button { app.compose = .gallery } label: { Label("Выбрать из галереи", systemImage: "photo.on.rectangle") }
                } label: {
                    PillLabel(title: "Фото чека", symbol: "camera")
                }
                Button { app.compose = .text } label: { PillLabel(title: "Написать", symbol: "keyboard") }
                    .buttonStyle(PressScale())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func open(_ item: SpendItem) {
        if isDemo {
            app.showToast("Это пример. Запиши свою трату, и пример исчезнет.")
            return
        }
        editing = records.first { $0.uid.uuidString == item.id }
    }
}

// MARK: - White card with today's spending

struct HeroCard: View {
    let today: Double
    let count: Int
    let week: Double
    let month: Double
    let average: Double
    let monthIncome: Double
    let budget: Double
    let currency: String
    @ObservedObject var motion: MotionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tx = reduceMotion ? 0 : Double(motion.tilt.width)
        let ty = reduceMotion ? 0 : Double(motion.tilt.height)
        let net = monthIncome - month

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Расходы за сегодня").eyebrow()
                Spacer()
                if count > 0 { Text(purchases(count)).eyebrow() }
            }
            Text(Money.signed(-today, currency))
                .font(.system(size: 44, weight: .semibold))
                .fontWidth(.expanded)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: today))
                .animation(.snappy, value: today)
                .padding(.top, 6)
                .padding(.bottom, 16)

            Rectangle().fill(Color.line).frame(height: 1)

            HStack(alignment: .top, spacing: 10) {
                stat("За неделю", Money.signed(-week, currency), .ink)
                stat("За месяц", Money.signed(-month, currency), .ink)
                if monthIncome > 0 {
                    stat("Остаток месяца", Money.signed(net, currency), net >= 0 ? .good : .bad)
                } else {
                    stat("В среднем в день", Money.signed(-average, currency), .ink)
                }
            }
            .padding(.top, 14)

            if budget > 0 {
                BudgetBar(spent: month, budget: budget, currency: currency)
                    .padding(.top, 14)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(RadialGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)],
                                             center: UnitPoint(x: 0.3 + tx * 0.9, y: 0.15 + ty * 0.9),
                                             startRadius: 0, endRadius: 260))
                        .blendMode(.softLight)
                }
        }
        .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
        .rotation3DEffect(.degrees(ty * 12), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(-tx * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(0.8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BudgetBar: View {
    let spent: Double
    let budget: Double
    let currency: String

    var body: some View {
        let cal = RuDate.cal
        let now = Date()
        let daysInMonth = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
        let day = Double(cal.component(.day, from: now))
        let pct = spent / budget
        let timePct = (day - 0.5) / daysInMonth
        let left = budget - spent
        let perDay = left / (daysInMonth - day + 1)
        let color: Color = pct > 1 ? .bad : (pct > timePct * 1.1 ? .warn : .good)

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Бюджет \(Money.format(budget, currency))")
                Spacer(minLength: 6)
                if left >= 0 {
                    Text("≈ \(Money.format(perDay, currency)) в день").foregroundStyle(Color.ink)
                } else {
                    Text("перерасход \(Money.format(-left, currency))").foregroundStyle(Color.bad)
                }
            }
            .font(.caption)
            .foregroundStyle(Color.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            ThinBar(value: pct, color: color, height: 6)
        }
    }
}
