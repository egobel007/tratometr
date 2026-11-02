import WidgetKit
import SwiftUI
import UIKit

// MARK: - Data from the app (shared app group; empty without a paid developer account)

struct WidgetSnapshot: Codable {
    var day: String
    var month: String
    var today: Double
    var week: Double
    var monthSpent: Double
    var monthIncome: Double
    var symbol: String
}

struct SpendEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Numbers as of `date`: a new day or month starts from zero
    var today: Double? {
        guard let s = snap else { return nil }
        return s.day == Self.iso.string(from: date) ? s.today : 0
    }
    var month: Double? {
        guard let s = snap else { return nil }
        return s.month == String(Self.iso.string(from: date).prefix(7)) ? s.monthSpent : 0
    }
    var monthIncome: Double {
        guard let s = snap, s.month == String(Self.iso.string(from: date).prefix(7)) else { return 0 }
        return s.monthIncome
    }
}

struct Provider: TimelineProvider {
    static let group = "group.com.egorbel.tratometr"
    static let key = "widget_snapshot"

    func placeholder(in context: Context) -> SpendEntry {
        SpendEntry(date: Date(), snap: WidgetSnapshot(day: "", month: "", today: 600, week: 4200, monthSpent: 32400, monthIncome: 0, symbol: "₽"))
    }

    func getSnapshot(in context: Context, completion: @escaping (SpendEntry) -> Void) {
        completion(SpendEntry(date: Date(), snap: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        let entries = [SpendEntry(date: now, snap: load()), SpendEntry(date: tomorrow, snap: load())]
        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }

    private func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: Self.group)?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Look

private extension Color {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { tc in
            let hex = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
    static let wBG = adaptive(0xFFFFFF, 0x171A21)
    static let wInk = adaptive(0x121419, 0xF1F2F5)
    static let wMuted = adaptive(0x666C7A, 0x99A0AE)
    static let wSurface2 = adaptive(0xE3E6EC, 0x21252E)
    static let wGood = adaptive(0x2B9A68, 0x43C08A)
    static let wBad = adaptive(0xD4473A, 0xF06A5D)
}

private let orbGradient = AngularGradient(colors: [Color(red: 1.0, green: 0.76, blue: 0.66), Color(red: 0.72, green: 0.68, blue: 1.0),
                                                   Color(red: 0.56, green: 0.90, blue: 0.85), Color(red: 1.0, green: 0.76, blue: 0.66)],
                                          center: .center)

private enum Links {
    static let record = URL(string: "tratometr://record")!
    static let scan = URL(string: "tratometr://scan")!
    static let text = URL(string: "tratometr://text")!
}

private func money(_ v: Double, _ symbol: String, sign: String = "−") -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    let s = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    return (v > 0.004 ? sign : "") + s + "\u{00A0}" + symbol
}

private struct MicBadge: View {
    var size: CGFloat
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(orbGradient))
    }
}

private struct SmallButton: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.wInk)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.wSurface2))
    }
}

private struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(Color.wMuted)
    }
}

// MARK: - Views per size

struct SpendWidgetView: View {
    let entry: SpendEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    private var symbol: String { entry.snap?.symbol ?? "₽" }

    private var small: some View {
        Group {
            if let today = entry.today {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "Сегодня")
                    Text(money(today, symbol))
                        .font(.system(size: 26, weight: .semibold))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.wInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Месяц " + money(entry.month ?? 0, symbol))
                        .font(.caption2)
                        .foregroundStyle(Color.wMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        MicBadge(size: 44)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    MicBadge(size: 64)
                    Text("Записать трату")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.wInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetURL(Links.record)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if let today = entry.today {
                    Eyebrow(text: "Сегодня")
                    Text(money(today, symbol))
                        .font(.system(size: 26, weight: .semibold))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.wInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Месяц " + money(entry.month ?? 0, symbol))
                        .font(.caption)
                        .foregroundStyle(Color.wMuted)
                        .lineLimit(1)
                    if entry.monthIncome > 0 {
                        let net = entry.monthIncome - (entry.month ?? 0)
                        Text("Остаток " + money(abs(net), symbol, sign: net >= 0 ? "+" : "−"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(net >= 0 ? Color.wGood : Color.wBad)
                            .lineLimit(1)
                    }
                } else {
                    Eyebrow(text: "Тратометр")
                    Text("Скажи, что потратил")
                        .font(.system(size: 17, weight: .semibold))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.wInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("Один тап, и запись")
                        .font(.caption)
                        .foregroundStyle(Color.wMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                Link(destination: Links.record) { MicBadge(size: 58) }
                HStack(spacing: 8) {
                    Link(destination: Links.scan) { SmallButton(symbol: "camera") }
                    Link(destination: Links.text) { SmallButton(symbol: "keyboard") }
                }
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill").font(.system(size: 22, weight: .semibold))
        }
        .widgetURL(Links.record)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let today = entry.today {
                Label("Тратометр", systemImage: "mic.fill").font(.caption2.weight(.semibold))
                Text("Сегодня " + money(today, symbol)).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text("Месяц " + money(entry.month ?? 0, symbol)).font(.caption).lineLimit(1)
            } else {
                Label("Тратометр", systemImage: "mic.fill").font(.headline)
                Text("Нажми и скажи трату").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(Links.record)
    }

    private var inline: some View {
        Group {
            if let today = entry.today {
                Text("\(Image(systemName: "mic.fill")) Сегодня \(money(today, symbol))")
            } else {
                Text("\(Image(systemName: "mic.fill")) Записать трату")
            }
        }
        .widgetURL(Links.record)
    }
}

// MARK: - Widget

struct SpendWidget: Widget {
    let kind = "TratometrWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SpendWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.wBG }
        }
        .configurationDisplayName("Тратометр")
        .description("Траты за сегодня и запись голосом в один тап")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct TratometrWidgets: WidgetBundle {
    var body: some Widget {
        SpendWidget()
    }
}
