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
                ScreenTitle(eyebrow: RuDate.headerToday(), title: RuDate.greeting() + "!")

                if isDemo { DemoBanner().padding(.bottom, 12).riseIn(0) }

                HeroCard(today: Stats.total(todayItems), count: todayItems.count, week: week, month: month,
                         average: month / dayOfMonth, budget: budget, currency: currency, motion: app.motion)
                    .riseIn(0.02)

                MonthStrip(income: monthIn, spent: month, currency: currency)
                    .padding(.top, 12)
                    .onTapGesture { app.go(.balance) }
                    .riseIn(0.06)

                orbBlock.riseIn(0.1)

                HStack {
                    Text("Последние").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Color.ink)
                    Spacer()
                    Button("Все") { app.go(.history) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.violet)
                }
                .padding(.top, 14)
                .padding(.bottom, 2)
                .riseIn(0.16)

                VStack(spacing: 0) {
                    ForEach(Array(recent)) { item in
                        Button { open(item) } label: { ExpenseRow(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .riseIn(0.2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    private var caption: String {
        switch app.mood {
        case .idle: return "Нажми на шар и скажи, что потратил или сколько пришло"
        case .listen: return "Слушаю…"
        case .think: return "Думаю…"
        }
    }

    private var orbBlock: some View {
        VStack(spacing: 6) {
            OrbView(engine: app.orb, paused: app.tab != .home)
                .frame(width: 260, height: 260)
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: app.mood)

            HStack(spacing: 8) {
                Menu {
                    Button { app.compose = .scan } label: { Label("Сфотографировать чек", systemImage: "doc.viewfinder") }
                    Button { app.compose = .gallery } label: { Label("Выбрать из галереи", systemImage: "photo.on.rectangle") }
                } label: {
                    PillLabel(title: "Чек", symbol: "camera.fill", tint: .sky)
                }
                Button { app.compose = .text } label: { PillLabel(title: "Написать", symbol: "keyboard.fill", tint: .violet) }
                    .buttonStyle(PressScale())
                Button { app.compose = .income } label: { PillLabel(title: "Доход", symbol: "plus.circle.fill", tint: .good) }
                    .buttonStyle(PressScale())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func open(_ item: SpendItem) {
        if isDemo {
            app.showToast("Это пример. Запиши свою трату, и пример исчезнет.")
            return
        }
        editing = records.first { $0.uid.uuidString == item.id }
    }
}

// MARK: - Sunny gradient card with today's spending

struct HeroCard: View {
    let today: Double
    let count: Int
    let week: Double
    let month: Double
    let average: Double
    let budget: Double
    let currency: String
    @ObservedObject var motion: MotionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tx = reduceMotion ? 0 : Double(motion.tilt.width)
        let ty = reduceMotion ? 0 : Double(motion.tilt.height)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Потрачено сегодня")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.9)
                Spacer()
                if count > 0 {
                    Text(purchases(count))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.22), in: Capsule())
                }
            }
            .foregroundStyle(Color.white.opacity(0.9))

            Text(Money.format(today, currency))
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: today))
                .animation(.snappy, value: today)
                .padding(.top, 4)
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 8) {
                stat("Неделя", week)
                stat("Месяц", month)
                stat("В день", average)
            }

            if budget > 0 {
                BudgetBar(spent: month, budget: budget, currency: currency)
                    .padding(.top, 14)
            }
        }
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Palette.hero)
                Circle().fill(Color.white.opacity(0.18)).frame(width: 180).offset(x: 140, y: -70).blur(radius: 2)
                Circle().fill(Color.sun.opacity(0.35)).frame(width: 140).offset(x: -150, y: 80).blur(radius: 30)
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(RadialGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)],
                                         center: UnitPoint(x: 0.3 + tx * 0.9, y: 0.15 + ty * 0.9),
                                         startRadius: 0, endRadius: 240))
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .shadow(color: Color.bubble.opacity(0.35), radius: 22, y: 12)
        .rotation3DEffect(.degrees(ty * 12), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(-tx * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
            Text(Money.format(value, currency))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: value))
                .animation(.snappy, value: value)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct BudgetBar: View {
    let spent: Double
    let budget: Double
    let currency: String
    @State private var shown = false

    var body: some View {
        let cal = RuDate.cal
        let now = Date()
        let daysInMonth = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
        let day = Double(cal.component(.day, from: now))
        let pct = spent / budget
        let timePct = (day - 0.5) / daysInMonth
        let left = budget - spent
        let perDay = left / (daysInMonth - day + 1)

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Бюджет \(Money.format(budget, currency))")
                Spacer(minLength: 6)
                Text(left >= 0 ? "можно ≈ \(Money.format(perDay, currency)) в день" : "перерасход \(Money.format(-left, currency))")
                    .bold()
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white).frame(width: geo.size.width * min(1, shown ? pct : 0))
                    Capsule()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 3, height: 14)
                        .offset(x: geo.size.width * min(1, timePct) - 1.5)
                }
            }
            .frame(height: 8)
        }
        .onAppear { withAnimation(.spring(response: 1, dampingFraction: 0.85).delay(0.3)) { shown = true } }
    }
}

/// "October: +90 000 in, −51 600 out, +38 400 left"
struct MonthStrip: View {
    let income: Double
    let spent: Double
    let currency: String

    var body: some View {
        let net = income - spent
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(RuDate.monthName(Date())).eyebrow()
                HStack(spacing: 10) {
                    Label(Money.format(income, currency), systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(Color.good)
                    Label(Money.format(spent, currency), systemImage: "arrow.up.circle.fill")
                        .foregroundStyle(Color.warm)
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(net >= 0 ? "в плюсе" : "в минусе")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.muted)
                Text(Money.signed(net, currency))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(net >= 0 ? Color.good : Color.bad)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.faint)
        }
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть баланс")
    }
}
