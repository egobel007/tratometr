import SwiftUI

// MARK: - Small building blocks

struct CategoryIcon: View {
    let category: SpendCategory
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(category.color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.33, style: .continuous))
    }
}

struct ExpenseRow: View {
    let item: SpendItem
    var showDate = true

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.note.isEmpty ? item.category.name : item.note)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if item.source == "voice" { Image(systemName: "mic.fill") }
                    if item.source == "photo" { Image(systemName: "camera.fill") }
                    Text(showDate ? RuDate.dayLabel(item.date) : RuDate.time(item.date))
                    Text("·")
                    Text(item.category.name)
                }
                .font(.caption)
                .foregroundStyle(Color.muted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.format(item.amount, item.currency))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
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
                    .background(Circle().fill(OrbGradient.angular))
                    .overlay(Circle().strokeBorder(Color.appBG, lineWidth: 5))
                    .shadow(color: Color(red: 0.55, green: 0.45, blue: 0.95).opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(PressScale())
            .offset(y: -16)
            .frame(maxWidth: .infinity)
            .sensoryFeedback(.impact(weight: .medium), trigger: tick)
            .accessibilityLabel("Записать трату")
            tab(.history, "list.bullet", "История")
            Button { app.showSettings = true } label: {
                item("slider.horizontal.3", "Настройки", active: false)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
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
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { app.tab = t }
        } label: {
            item(symbol, title, active: app.tab == t)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func item(_ symbol: String, _ title: String, active: Bool) -> some View {
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
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
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
            if let undo = message.undo {
                Button("Отменить") {
                    undo()
                    withAnimation { app.toast = nil }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.warm)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
        .padding(.horizontal, 16)
    }
}
