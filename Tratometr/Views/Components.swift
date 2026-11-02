import SwiftUI

// MARK: - Icons

/// Soft tinted tile with a coloured symbol.
struct ItemIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.33, style: .continuous))
    }
}

struct CategoryIcon: View {
    let category: SpendCategory
    var size: CGFloat = 42
    var body: some View { ItemIcon(symbol: category.symbol, color: category.color, size: size) }
}

// MARK: - Rows

struct ExpenseRow: View {
    let item: SpendItem
    var showDate = true

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(symbol: item.symbol, color: item.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.note.isEmpty ? item.detailName : item.note)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(showDate ? RuDate.dayLabel(item.date) : RuDate.time(item.date))
                    Text("·")
                    Text(item.detailName)
                    if !item.people.isEmpty {
                        Text("·")
                        Image(systemName: "heart.fill").font(.system(size: 9))
                        Text(item.people.joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.muted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text((item.isIncome ? "+" : "−") + Money.format(item.amount, item.currency))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.isIncome ? Color.good : Color.ink)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// "Сегодня   +40 000 ₽  −1 250 ₽"
struct DayHeader: View {
    let group: DayGroup
    let currency: String

    var body: some View {
        let main = group.items.filter { $0.currency == currency }
        let spent = Stats.total(main.filter { !$0.isIncome })
        let came = Stats.total(main.filter { $0.isIncome })
        HStack(spacing: 8) {
            Text(RuDate.dayLabel(group.day)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
            Spacer()
            if came > 0 { Text("+" + Money.format(came, currency)).foregroundStyle(Color.good) }
            if spent > 0 { Text("−" + Money.format(spent, currency)).foregroundStyle(Color.muted) }
        }
        .font(.subheadline)
        .monospacedDigit()
        .textCase(nil)
    }
}

struct DemoBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
            (Text("Сейчас здесь пример. ").bold().foregroundStyle(Color.ink) +
             Text("Запиши первую трату, и он сменится твоими данными."))
        }
        .font(.footnote)
        .foregroundStyle(Color.muted)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.faint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

struct PillLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.line))
    }
}

struct ScreenTitle: View {
    let eyebrow: String
    let title: String
    var showSettings = false
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).eyebrow()
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            if showSettings {
                Button { app.showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .frame(width: 40, height: 40)
                        .background(Color.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Color.line))
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Настройки")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Color.muted)
    }
}

/// Thin progress line
struct ThinBar: View {
    let value: Double
    var color: Color = .ink
    var height: CGFloat = 6
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surface2)
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, shown ? value : 0)))
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) { shown = true } }
    }
}

extension View {
    func eyebrow() -> some View {
        self.font(.system(size: 11, weight: .medium, design: .monospaced))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Color.muted)
    }

    func card() -> some View {
        self.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }

    func riseIn(_ delay: Double) -> some View { modifier(RiseIn(delay: delay)) }
}

// MARK: - Motion

/// Content rises in with a slight 3D tilt the first time it appears.
struct RiseIn: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .rotation3DEffect(.degrees(shown ? 0 : 10), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .onAppear {
                if reduceMotion { shown = true; return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

struct Tilt3D: ViewModifier {
    let angle: Double
    let offset: CGFloat
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
            .offset(y: offset)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Tab bar with the record button in the middle

struct TabBar: View {
    @EnvironmentObject private var app: AppState
    @State private var tick = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            tab(.home, "house", "Главная")
            tab(.stats, "chart.pie", "Аналитика")
            Button {
                tick += 1
                app.compose = .voice
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(Palette.orb))
                    .overlay(Circle().strokeBorder(Color.appBG, lineWidth: 5))
                    .shadow(color: Color(red: 0.55, green: 0.45, blue: 0.95).opacity(0.3), radius: 12, y: 6)
            }
            .buttonStyle(PressScale())
            .offset(y: -16)
            .frame(maxWidth: .infinity)
            .sensoryFeedback(.impact(weight: .medium), trigger: tick)
            .accessibilityLabel("Записать")
            tab(.balance, "creditcard", "Баланс")
            tab(.history, "list.bullet", "История")
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .background {
            Color.appBG
                .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tab(_ t: AppTab, _ symbol: String, _ title: String) -> some View {
        let active = app.tab == t
        return Button { app.go(t) } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: active ? .semibold : .regular))
                    .symbolEffect(.bounce, value: active)
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(active ? Color.ink : Color.faint)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ToastView: View {
    let message: ToastMessage
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 14) {
            Text(message.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.appBG)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = message.actionTitle, let action = message.action {
                Button(title) {
                    withAnimation { app.toast = nil }
                    action()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.warm)
            }
            if let undo = message.undo {
                Button {
                    undo()
                    withAnimation { app.toast = nil }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appBG.opacity(0.75))
                }
                .accessibilityLabel("Отменить")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        .padding(.horizontal, 16)
    }
}
