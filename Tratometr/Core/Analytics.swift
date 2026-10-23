import Foundation
import SwiftUI

enum Period: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "День"
        case .week: return "Неделя"
        case .month: return "Месяц"
        }
    }

    var prevPhrase: String {
        switch self {
        case .day: return "вчерашнему дню"
        case .week: return "прошлой неделе"
        case .month: return "прошлому месяцу"
        }
    }
}

struct CatTotal: Identifiable {
    let category: SpendCategory
    let amount: Double
    let count: Int
    var id: String { category.rawValue }
}

struct DayTotal: Identifiable {
    let date: Date
    let total: Double
    let isToday: Bool
    var id: Date { date }
}

struct Insight: Identifiable {
    enum Tone { case good, warn, bad, neutral }
    let id = UUID()
    let tone: Tone
    let symbol: String
    let text: String

    var color: Color {
        switch tone {
        case .good: return .good
        case .warn: return .warn
        case .bad: return .bad
        case .neutral: return .muted
        }
    }
}

enum Stats {
    static func interval(_ p: Period, offset: Int, now: Date = Date()) -> DateInterval {
        let cal = RuDate.cal
        switch p {
        case .day:
            let start = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            let w = cal.dateInterval(of: .weekOfYear, for: now)!
            let start = cal.date(byAdding: .weekOfYear, value: offset, to: w.start)!
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: 7, to: start)!)
        case .month:
            let m = cal.dateInterval(of: .month, for: now)!
            let start = cal.date(byAdding: .month, value: offset, to: m.start)!
            return DateInterval(start: start, end: cal.date(byAdding: .month, value: 1, to: start)!)
        }
    }

    static func filter(_ items: [SpendItem], _ iv: DateInterval) -> [SpendItem] {
        items.filter { $0.date >= iv.start && $0.date < iv.end }
    }

    static func total(_ items: [SpendItem]) -> Double { items.reduce(0) { $0 + $1.amount } }

    static func byCategory(_ items: [SpendItem]) -> [CatTotal] {
        Dictionary(grouping: items, by: \.category)
            .map { CatTotal(category: $0.key, amount: total($0.value), count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
    }

    static func daily(_ items: [SpendItem], _ iv: DateInterval) -> [DayTotal] {
        let cal = RuDate.cal
        let today = cal.startOfDay(for: Date())
        var out: [DayTotal] = []
        var d = iv.start
        while d < iv.end {
            let next = cal.date(byAdding: .day, value: 1, to: d)!
            out.append(DayTotal(date: d, total: total(filter(items, DateInterval(start: d, end: next))), isToday: d == today))
            d = next
        }
        return out
    }

    /// Days of the period that have already happened (at least 1)
    static func elapsedDays(_ iv: DateInterval) -> Int {
        let full = Int((iv.duration / 86400).rounded())
        let gone = Int(ceil(min(Date(), iv.end).timeIntervalSince(iv.start) / 86400))
        return max(1, min(full, gone))
    }

    static func label(_ p: Period, offset: Int) -> String {
        let iv = interval(p, offset: offset)
        let s = RuDate.parts(iv.start)
        let e = RuDate.parts(iv.end.addingTimeInterval(-1))
        switch p {
        case .day:
            let l = RuDate.dayLabel(iv.start)
            return ["Сегодня", "Вчера", "Позавчера"].contains(l) ? l : "\(s.day) \(RuDate.monthsGen[s.month])"
        case .week:
            if offset == 0 { return "Эта неделя" }
            if offset == -1 { return "Прошлая неделя" }
            if s.month == e.month { return "\(s.day)–\(e.day) \(RuDate.monthsShort[s.month])" }
            return "\(s.day) \(RuDate.monthsShort[s.month]) – \(e.day) \(RuDate.monthsShort[e.month])"
        case .month:
            let thisYear = RuDate.parts(Date()).year
            return RuDate.months[s.month] + (s.year != thisYear ? " \(s.year)" : "")
        }
    }

    static func insights(period: Period, offset: Int, current: [SpendItem], previous: [SpendItem],
                         currency: String, budget: Double) -> [Insight] {
        let total = self.total(current)
        guard total > 0 else {
            return [Insight(tone: .neutral, symbol: "chart.pie", text: "В этом периоде пока нечего анализировать.")]
        }
        let ptotal = self.total(previous)
        let m = Dictionary(grouping: current, by: \.category).mapValues { self.total($0) }
        let pm = Dictionary(grouping: previous, by: \.category).mapValues { self.total($0) }
        func f(_ v: Double) -> String { Money.format(v, currency) }
        func pct(_ v: Double) -> Int { Int((v / total * 100).rounded()) }
        var out: [Insight] = []

        if let top = m.max(by: { $0.value < $1.value }) {
            out.append(Insight(tone: .neutral, symbol: "chart.pie.fill",
                               text: "**\(top.key.name)** забирает \(pct(top.value))% всех трат: \(f(top.value))."))
        }

        if ptotal > 0 {
            let keys = Set(m.keys).union(pm.keys)
            let diffs = keys.map { (cat: $0, diff: (m[$0] ?? 0) - (pm[$0] ?? 0)) }
            if let up = diffs.filter({ $0.diff > 0 }).max(by: { $0.diff < $1.diff }), up.diff > total * 0.04 {
                out.append(Insight(tone: .warn, symbol: "arrow.up.right",
                                   text: "**\(up.cat.name)**: на \(f(up.diff)) больше, чем по \(period.prevPhrase). Здесь проще всего срезать."))
            }
            if let down = diffs.filter({ $0.diff < 0 }).min(by: { $0.diff < $1.diff }), -down.diff > total * 0.04 {
                out.append(Insight(tone: .good, symbol: "arrow.down.right",
                                   text: "**\(down.cat.name)**: на \(f(-down.diff)) меньше, чем по \(period.prevPhrase). Хорошо держишься."))
            }
        }

        let small = CurrencyInfo.get(currency).small
        let smalls = current.filter { $0.amount <= small }
        if smalls.count >= 4 {
            let s = self.total(smalls)
            out.append(Insight(tone: .warn, symbol: "circle.grid.3x3.fill",
                               text: "Мелочь до \(f(small)): **\(purchases(smalls.count))** на \(f(s)). Это \(pct(s))% периода, и её обычно не замечаешь."))
        }

        let days = Double(elapsedDays(interval(period, offset: offset)))
        if period != .day, let coffee = m[.coffee] {
            out.append(Insight(tone: .neutral, symbol: "cup.and.saucer.fill",
                               text: "Кофе и перекусы в таком темпе: около **\(f(coffee / days * 30))** в месяц, это \(f(coffee / days * 365)) в год."))
        }

        if period == .month && offset == 0 {
            let cal = RuDate.cal
            let now = Date()
            let dim = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
            let day = Double(cal.component(.day, from: now))
            let forecast = total / day * dim
            if budget > 0 {
                if forecast > budget {
                    let perDay = max(0, (budget - total) / (dim - day + 1))
                    out.append(Insight(tone: .bad, symbol: "flag.fill",
                                       text: "При таком темпе месяц закроется на **\(f(forecast))**, это на \(f(forecast - budget)) больше бюджета. Чтобы уложиться, держи до \(f(perDay)) в день."))
                } else {
                    out.append(Insight(tone: .good, symbol: "flag.fill",
                                       text: "Прогноз на месяц: **\(f(forecast))**. В бюджет \(f(budget)) укладываешься, запас около \(f(budget - forecast))."))
                }
            } else {
                out.append(Insight(tone: .neutral, symbol: "flag",
                                   text: "Прогноз на месяц при таком темпе: **\(f(forecast))**. Задай бюджет в настройках, и я покажу, сколько можно тратить в день."))
            }
        }

        if period != .day && current.count >= 10 {
            let cal = RuDate.cal
            var sums = [Double](repeating: 0, count: 7)
            var counts = [Double](repeating: 0, count: 7)
            for x in current { sums[cal.component(.weekday, from: x.date) - 1] += x.amount }
            let activeDays = Set(current.map { cal.startOfDay(for: $0.date) })
            for d in activeDays { counts[cal.component(.weekday, from: d) - 1] += 1 }
            let avgs = (0..<7).map { counts[$0] > 0 ? sums[$0] / counts[$0] : 0 }
            let mean = total / Double(max(1, activeDays.count))
            if let mx = avgs.indices.max(by: { avgs[$0] < avgs[$1] }), avgs[mx] > mean * 1.3 {
                out.append(Insight(tone: .neutral, symbol: "calendar",
                                   text: "Самый дорогой день недели: **\(RuDate.weekdays[mx])**, в среднем \(f(avgs[mx])) против \(f(mean)) в обычный день."))
            }
        }
        return out
    }

    /// Plain-text summary of a period for Claude's advice
    static func summary(period: Period, offset: Int, current: [SpendItem], previous: [SpendItem],
                        currency: String, budget: Double) -> String {
        func f(_ v: Double) -> String { Money.format(v, currency) }
        let m = Dictionary(grouping: current, by: \.category).mapValues { total($0) }
        let pm = Dictionary(grouping: previous, by: \.category).mapValues { total($0) }
        let cats = Set(m.keys).union(pm.keys).sorted { (m[$0] ?? 0) > (m[$1] ?? 0) }
        let lines = cats.map { c in
            "- \(c.name): \(f(m[c] ?? 0)) / \(f(pm[c] ?? 0)), покупок \(current.filter { $0.category == c }.count)"
        }.joined(separator: "\n")
        let big = current.sorted { $0.amount > $1.amount }.prefix(6)
            .map { "\($0.note) (\($0.category.name)): \(f($0.amount))" }.joined(separator: "; ")
        let small = CurrencyInfo.get(currency).small
        let smalls = current.filter { $0.amount <= small }
        return """
        Период: \(label(period, offset: offset)) (\(period.title.lowercased())), валюта \(currency).
        Итого: \(f(total(current))). Прошлый такой же период: \(f(total(previous))).
        По категориям (сейчас / прошлый период):
        \(lines)
        Крупнейшие траты: \(big.isEmpty ? "нет" : big).
        Мелкие покупки до \(f(small)): \(smalls.count) шт. на \(f(total(smalls))).
        Бюджет на месяц: \(budget > 0 ? f(budget) : "не задан").
        """
    }
}

// MARK: - Demo data shown until the first real expense

enum DemoData {
    private struct RNG {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
    }

    static func make(currency: String) -> [SpendItem] {
        let c = CurrencyInfo.get(currency)
        var rng = RNG(state: 11)
        let templates: [(SpendCategory, String, Double, Double, Double)] = [
            (.coffee, "Капучино", 180, 320, 0.8), (.coffee, "Круассан", 150, 240, 0.3),
            (.food, "Пятёрочка", 600, 3400, 0.5), (.cafe, "Обед", 450, 1100, 0.45),
            (.transport, "Метро", 62, 62, 0.65), (.taxi, "Такси", 350, 950, 0.28),
            (.fun, "Кино", 450, 900, 0.06), (.health, "Аптека", 300, 1400, 0.07),
            (.cafe, "Доставка ужина", 900, 1900, 0.12), (.clothes, "Кроссовки", 5200, 7400, 0.02),
            (.shop, "Наушники", 2500, 4900, 0.015), (.beauty, "Стрижка", 1500, 1500, 0.03)
        ]
        func money(_ rub: Double) -> Double {
            let v = (rub * c.demo / c.step).rounded() * c.step
            return (max(c.step, v) * 100).rounded() / 100
        }
        let cal = RuDate.cal
        let now = Date()
        var out: [SpendItem] = []
        for d in 0..<62 {
            guard let day = cal.date(byAdding: .day, value: -d, to: cal.startOfDay(for: now)) else { continue }
            for t in templates {
                guard rng.next() <= t.4 else { continue }
                let date = day.addingTimeInterval((8 + rng.next() * 13) * 3600)
                let amount = money(t.2 + (t.3 - t.2) * rng.next())
                if date > now { continue }
                out.append(SpendItem(id: "demo\(out.count)", amount: amount, currency: currency, category: t.0,
                                     note: t.1, date: date, source: "voice"))
            }
            let dom = cal.component(.day, from: day)
            if dom == 10 {
                out.append(SpendItem(id: "demo\(out.count)", amount: money(5200), currency: currency, category: .home,
                                     note: "Коммуналка", date: day.addingTimeInterval(11 * 3600), source: "text"))
            }
            if dom == 3 {
                out.append(SpendItem(id: "demo\(out.count)", amount: money(899), currency: currency, category: .subs,
                                     note: "Подписки", date: day.addingTimeInterval(9 * 3600), source: "text"))
            }
        }
        return out.filter { $0.date <= now }.sorted { $0.date > $1.date }
    }
}
