import SwiftUI

// MARK: - Icons

/// Bright rounded tile with a white symbol.
struct ItemIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                    .fill(color.gradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                                                 startPoint: .top, endPoint: .center))
                    )
            }
            .shadow(color: color.opacity(0.35), radius: 6, y: 3)
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
                Text(item.note.isEmpty ? item.kindName : item.note)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if item.source == "voice" { Image(systemName: "mic.fill") }
                    if item.source == "photo" { Image(systemName: "camera.fill") }
                    Text(showDate ? RuDate.dayLabel(item.date) : RuDate.time(item.date))
                    Text("·")
                    Text(item.kindName)
                }
                .font(.caption)
                .foregroundStyle(Color.muted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.isIncome ? "+" + Money.format(item.amount, item.currency) : Money.format(item.amount, item.currency))
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(item.isIncome ? Color.good : Color.ink)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct DemoBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.violet)
            (Text("Сейчас здесь пример. ").bold().foregroundStyle(Color.ink) +
             Text("Запиши первую трату или поступление, и он сменится твоими данными."))
        }
        .font(.footnote)
        .foregroundStyle(Color.muted)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.sun.opacity(0.18), Color.bubble.opacity(0.14), Color.violet.opacity(0.14)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

struct PillLabel: View {
    let title: String
    let symbol: String
    var tint: Color = .violet
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).foregroundStyle(Color.ink)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.surface, in: Capsule())
        .shadow(color: tint.opacity(0.18), radius: 8, y: 3)
    }
}

extension View {
    func eyebrow() -> some View {
        self.font(.system(size: 11, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(Color.muted)
    }

    func card() -> some View {
        self.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color.violet.opacity(0.10), radius: 18, y: 8)
    }

    func riseIn(_ delay: Double) -> some View { modifier(RiseIn(delay: delay)) }
}

struct ScreenTitle: View {
    let eyebrow: String
    let title: String
    var showSettings = true
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).eyebrow()
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            if showSettings {
                Button { app.showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.violet)
                        .frame(width: 42, height: 42)
                        .background(Color.surface, in: Circle())
                        .shadow(color: Color.violet.opacity(0.15), radius: 8, y: 3)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Настройки")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Background with softly drifting colour blobs

struct AppBackground: View {
    @State private var drift = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let k = scheme == .dark ? 0.55 : 1.0
        ZStack {
            Color.appBG
            Circle().fill(Color.sun.opacity(0.32 * k)).frame(width: 340, height: 340).blur(radius: 90)
                .offset(x: drift ? -150 : -90, y: drift ? -330 : -270)
            Circle().fill(Color.bubble.opacity(0.26 * k)).frame(width: 320, height: 320).blur(radius: 90)
                .offset(x: drift ? 170 : 110, y: drift ? -170 : -240)
            Circle().fill(Color.mintPop.opacity(0.22 * k)).frame(width: 360, height: 360).blur(radius: 100)
                .offset(x: drift ? -90 : 30, y: drift ? 330 : 270)
            Circle().fill(Color.sky.opacity(0.18 * k)).frame(width: 300, height: 300).blur(radius: 100)
                .offset(x: drift ? 160 : 120, y: drift ? 160 : 230)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
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
            .offset(y: shown ? 0 : 18)
            .rotation3DEffect(.degrees(shown ? 0 : 12), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .onAppear {
                if reduceMotion { shown = true; return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(delay)) { shown = true }
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

/// Colourful confetti burst, fired by changing `trigger`.
struct ConfettiBurst: View {
    let trigger: Int
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static func rand(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i * 127 + k * 311) + 0.5) * 43758.5453
        return x - floor(x)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { context in
            Canvas { gc, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                guard t >= 0, t < 2.0 else { return }
                let colors = Palette.party
                for i in 0..<80 {
                    let angle = -Double.pi / 2 + (Self.rand(i, 1) - 0.5) * 2.2
                    let speed = 420 + Self.rand(i, 2) * 520
                    let x = size.width / 2 + cos(angle) * speed * t
                    let y = size.height * 0.45 + sin(angle) * speed * t + 0.5 * 1100 * t * t
                    var g = gc
                    g.opacity = max(0, 1 - t / 2.0)
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .radians(t * (4 + Self.rand(i, 3) * 8)))
                    let w = 6 + Self.rand(i, 4) * 6
                    let rect = CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)
                    g.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { start = nil }
        }
    }
}

// MARK: - Floating tab bar with the record button in the middle

struct TabBar: View {
    @EnvironmentObject private var app: AppState
    @State private var tick = 0

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tab(.home, "house.fill", "Главная")
            tab(.balance, "creditcard.fill", "Баланс")
            Button {
                tick += 1
                app.compose = .voice
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Palette.orb))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 3))
                    .shadow(color: Color.bubble.opacity(0.45), radius: 12, y: 6)
            }
            .buttonStyle(PressScale())
            .offset(y: -14)
            .frame(maxWidth: .infinity)
            .sensoryFeedback(.impact(weight: .medium), trigger: tick)
            .accessibilityLabel("Записать")
            tab(.stats, "chart.pie.fill", "Аналитика")
            tab(.history, "list.bullet", "История")
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.25)))
        .shadow(color: Color.violet.opacity(0.18), radius: 20, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    private func tab(_ t: AppTab, _ symbol: String, _ title: String) -> some View {
        let active = app.tab == t
        return Button { app.go(t) } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(active ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.faint))
                    .symbolEffect(.bounce, value: active)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(active ? Color.ink : Color.faint)
            }
            .padding(.vertical, 5)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
            if let undo = message.undo {
                Button("Отменить") {
                    undo()
                    withAnimation { app.toast = nil }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.sun)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.16, green: 0.13, blue: 0.30), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        .padding(.horizontal, 16)
    }
}
