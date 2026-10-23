import Foundation
import SwiftUI
import UIKit
import Security

// MARK: - Money

enum Money {
    private static func formatter(_ digits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f
    }
    private static let f0 = formatter(0)
    private static let f2 = formatter(2)

    static func format(_ value: Double, _ code: String) -> String {
        let c = CurrencyInfo.get(code)
        let fractional = c.decimals > 0 && abs(value - value.rounded()) > 0.004
        let s = (fractional ? f2 : f0).string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        return s + "\u{00A0}" + c.symbol
    }

    /// "+38 400 ₽" / "−12 000 ₽"
    static func signed(_ value: Double, _ code: String) -> String {
        if abs(value) < 0.005 { return format(0, code) }
        return (value > 0 ? "+" : "−") + format(abs(value), code)
    }

    /// For text fields: "1500" or "12,50"
    static func plain(_ value: Double) -> String {
        if value == value.rounded() { return String(format: "%.0f", value) }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func parse(_ s: String) -> Double {
        let cleaned = s.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }
        return Double(cleaned) ?? 0
    }
}

func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let n100 = abs(n) % 100, n10 = n100 % 10
    if n100 > 10 && n100 < 20 { return many }
    if n10 > 1 && n10 < 5 { return few }
    if n10 == 1 { return one }
    return many
}

func purchases(_ n: Int) -> String { "\(n) \(plural(n, "покупка", "покупки", "покупок"))" }

// MARK: - Russian dates

enum RuDate {
    static let months = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
    static let monthsGen = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let monthsShort = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    static let monthsShortNom = ["янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    /// index = Calendar weekday - 1 (Sunday first)
    static let weekdays = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
    static let weekdaysShort = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]

    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }()

    static func parts(_ d: Date) -> (day: Int, month: Int, year: Int, weekday: Int) {
        let c = cal.dateComponents([.day, .month, .year, .weekday], from: d)
        return (c.day ?? 1, (c.month ?? 1) - 1, c.year ?? 2026, (c.weekday ?? 1) - 1)
    }

    static func dayLabel(_ d: Date) -> String {
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        if diff == 0 { return "Сегодня" }
        if diff == 1 { return "Вчера" }
        if diff == 2 { return "Позавчера" }
        let p = parts(d)
        return "\(p.day) \(monthsGen[p.month]), \(weekdaysShort[p.weekday])"
    }

    static func headerToday() -> String {
        let p = parts(Date())
        return "\(weekdays[p.weekday]), \(p.day) \(monthsGen[p.month])"
    }

    static func longToday() -> String {
        let p = parts(Date())
        return "\(p.day) \(monthsGen[p.month]) \(p.year), \(weekdays[p.weekday])"
    }

    static func greeting() -> String {
        let h = cal.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    static func monthName(_ d: Date) -> String { months[parts(d).month] }

    static func time(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func iso(_ d: Date) -> String {
        let p = parts(d)
        return String(format: "%04d-%02d-%02d", p.year, p.month + 1, p.day)
    }

    static func date(daysAgo: Int) -> Date {
        if daysAgo <= 0 { return Date() }
        let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date())
        return cal.date(byAdding: .hour, value: 12, to: day) ?? day
    }
}

// MARK: - Regex helpers (ICU, works with Cyrillic)

extension String {
    func splitRegex(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [self] }
        let ns = self as NSString
        var out: [String] = []
        var last = 0
        for m in re.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func replacingRegex(_ pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return self }
        return re.stringByReplacingMatches(in: self, range: NSRange(location: 0, length: (self as NSString).length), withTemplate: template)
    }

    func captureGroups(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    func allCaptureGroups(_ pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}

// MARK: - Keychain (for the optional Claude API key)

enum Keychain {
    static func save(_ value: String, for key: String) {
        delete(key)
        guard !value.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let s = String(data: data, encoding: .utf8)
        return (s?.isEmpty ?? true) ? nil : s
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Theme: bright, sunny, friendly

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let appBG = adaptive(0xFBF9FF, 0x14112B)
    static let surface = adaptive(0xFFFFFF, 0x201C3D)
    static let surface2 = adaptive(0xF1EEFB, 0x2C2752)
    static let ink = adaptive(0x1F1A3A, 0xF6F4FF)
    static let muted = adaptive(0x6F6A8E, 0xABA6CF)
    static let faint = adaptive(0xA9A4C6, 0x716C99)
    static let line = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.09) : UIColor(hex: 0x1F1A3A, alpha: 0.07) })
    static let warm = adaptive(0xFF6B5A, 0xFF8A7B)
    static let good = adaptive(0x16B07A, 0x3EDC9E)
    static let warn = adaptive(0xF29A12, 0xFFC04D)
    static let bad = adaptive(0xF4475B, 0xFF6F7F)

    // party palette
    static let sun = Color(red: 1.0, green: 0.74, blue: 0.27)
    static let bubble = Color(red: 1.0, green: 0.44, blue: 0.66)
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let mintPop = Color(red: 0.20, green: 0.86, blue: 0.70)
    static let sky = Color(red: 0.30, green: 0.66, blue: 1.0)
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.35)
}

enum Palette {
    static let party: [Color] = [.sun, .bubble, .violet, .mintPop, .sky, .coral]
    static let orb = AngularGradient(colors: [.sun, .bubble, .violet, .sky, .mintPop, .sun], center: .center)
    static let hero = LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.30), .bubble, .violet],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
    static let plus = LinearGradient(colors: [Color(red: 0.16, green: 0.80, blue: 0.62), Color(red: 0.25, green: 0.68, blue: 1.0)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
    static let minus = LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.35), Color(red: 0.98, green: 0.33, blue: 0.52)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accent = LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.30), .bubble],
                                       startPoint: .leading, endPoint: .trailing)
}
