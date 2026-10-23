import Foundation

/// Offline parser for spoken Russian like
/// «кофе 250, такси до работы 640 и вчера продукты полторы тысячи».
enum LocalParser {
    static let numberWords: [String: Double] = [
        "ноль": 0, "один": 1, "одна": 1, "одну": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
        "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11, "двенадцать": 12,
        "тринадцать": 13, "четырнадцать": 14, "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17,
        "восемнадцать": 18, "девятнадцать": 19, "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50,
        "шестьдесят": 60, "семьдесят": 70, "восемьдесят": 80, "девяносто": 90, "сто": 100, "двести": 200,
        "триста": 300, "четыреста": 400, "пятьсот": 500, "шестьсот": 600, "семьсот": 700, "восемьсот": 800,
        "девятьсот": 900
    ]

    static let stop: Set<String> = [
        "я", "мы", "потратил", "потратила", "потратили", "купил", "купила", "купили", "заплатил", "заплатила",
        "оплатил", "оплатила", "взял", "взяла", "за", "на", "в", "во", "около", "примерно", "где-то", "еще",
        "вчера", "сегодня", "позавчера", "руб", "рубля", "рублей", "рубль", "р", "евро", "доллар", "доллара",
        "долларов", "бакса", "баксов", "тенге", "фунт", "фунтов", "по", "тысяч", "тысячи", "тысяча", "тыс",
        "штук", "штуки", "с", "половиной", "ну", "вот", "короче", "типа", "это", "было", "была", "был", "и", "а", "плюс"
    ]

    static func parse(_ text: String, currency: String) -> [DraftExpense] {
        let src = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        let parts = src.splitRegex(#"[;\n]+|,(?!\d)|\.(?=\s|$)|\s+(?:и|а|плюс|потом|затем|также)\s+"#)
        var out: [DraftExpense] = []
        var carry = ""
        var days = 0
        for part in parts {
            if part.contains("позавчера") { days = 2 }
            else if part.contains("вчера") { days = 1 }
            else if part.contains("сегодня") { days = 0 }
            let p = (carry + " " + part).trimmingCharacters(in: .whitespaces)
            guard let amount = findAmount(p), amount > 0 else { carry = p; continue }
            carry = ""
            let cat = detectCategory(p)
            out.append(DraftExpense(amount: amount, currency: detectCurrency(p, fallback: currency), category: cat,
                                    note: note(p, cat), date: RuDate.date(daysAgo: days), source: "voice", raw: text))
        }
        if !carry.isEmpty, var last = out.popLast() {
            if last.category == .other { last.category = detectCategory(carry) }
            out.append(last)
        }
        return out
    }

    // MARK: amount

    static func findAmount(_ chunk: String) -> Double? {
        let s = chunk
            .replacingRegex(#"(\d)[\s  ](?=\d{3}(?!\d))"#, with: "$1")
            .replacingRegex(#"(\d),(\d)"#, with: "$1.$2")
        let tokens = s.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "«»\"()!?:")) }
            .filter { !$0.isEmpty }
        var nums: [(value: Double, byPrice: Bool)] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            let afterPo = i > 0 && tokens[i - 1] == "по"
            if let g = t.captureGroups(#"^(\d+(?:\.\d+)?)(к|k|т|тыс|р|₽|€|\$)?\.?$"#) {
                var v = Double(g[1]) ?? 0
                let suffix = g[2].lowercased()
                if ["к", "k", "т", "тыс"].contains(suffix) {
                    v *= 1000
                } else if i + 1 < tokens.count, tokens[i + 1].hasPrefix("тыс") || tokens[i + 1].hasPrefix("тыщ") {
                    v *= 1000
                    i += 1
                }
                nums.append((v, afterPo))
                i += 1
                continue
            }
            if let w = wordsNumber(tokens, from: i) {
                nums.append((w.value, afterPo))
                i += max(1, w.used)
                continue
            }
            i += 1
        }
        guard !nums.isEmpty else { return nil }
        if nums.count > 1, let by = nums.firstIndex(where: { $0.byPrice }),
           let q = nums.indices.first(where: { $0 != by && nums[$0].value <= 20 }) {
            return nums[by].value * nums[q].value
        }
        return nums.map(\.value).max()
    }

    static func wordsNumber(_ tokens: [String], from start: Int) -> (value: Double, used: Int)? {
        var total = 0.0, cur = 0.0, used = 0, any = false
        var i = start
        while i < tokens.count {
            let t = tokens[i]
            if let v = numberWords[t] { cur += v; any = true; used += 1; i += 1; continue }
            if t.hasPrefix("полтор") { cur += 1.5; any = true; used += 1; i += 1; continue }
            if t.hasPrefix("полтинник") { cur += 50; any = true; used += 1; i += 1; continue }
            if t == "с", cur > 0, i + 1 < tokens.count, tokens[i + 1].hasPrefix("половин") {
                cur += 0.5; used += 2; i += 2; continue
            }
            if t.hasPrefix("тысяч") || t.hasPrefix("тыщ") || t == "тыс" {
                total += (cur == 0 ? 1 : cur) * 1000; cur = 0; any = true; used += 1; i += 1
                if i + 1 < tokens.count, tokens[i] == "с", tokens[i + 1].hasPrefix("половин") {
                    total += 500; used += 2; i += 2
                }
                continue
            }
            if t.hasPrefix("косар") || t.hasPrefix("косых") { total += (cur == 0 ? 1 : cur) * 1000; cur = 0; any = true; used += 1; i += 1; continue }
            if t.hasPrefix("пятихат") || t.hasPrefix("пятисотк") { total += (cur == 0 ? 1 : cur) * 500; cur = 0; any = true; used += 1; i += 1; continue }
            if t.hasPrefix("сотк") || t.hasPrefix("сотн") || t.hasPrefix("сотен") { total += (cur == 0 ? 1 : cur) * 100; cur = 0; any = true; used += 1; i += 1; continue }
            break
        }
        return any ? (total + cur, used) : nil
    }

    // MARK: currency, category, note

    static func detectCurrency(_ s: String, fallback: String) -> String {
        if s.contains("евро") || s.contains("€") { return "EUR" }
        if s.contains("доллар") || s.contains("бакс") || s.contains("$") { return "USD" }
        if s.contains("тенге") || s.contains("₸") { return "KZT" }
        if s.contains("фунт") || s.contains("£") { return "GBP" }
        if s.contains("руб") || s.contains("₽") { return "RUB" }
        return fallback
    }

    static func detectCategory(_ s: String) -> SpendCategory {
        let text = s.lowercased().replacingOccurrences(of: "ё", with: "е")
        var best = SpendCategory.other
        var score = 0
        for c in SpendCategory.allCases {
            for k in c.keywords where text.contains(k) && k.count > score {
                best = c
                score = k.count
            }
        }
        return best
    }

    static func note(_ chunk: String, _ cat: SpendCategory) -> String {
        let cleaned = chunk
            .replacingRegex(#"\d[\d.,]*(?:\s*(?:к|k|тыс)(?![а-яa-z]))?"#, with: " ")
            .replacingRegex(#"[₽€$£₸«»"]"#, with: " ")
        let words = cleaned.components(separatedBy: .whitespaces).filter { w in
            !w.isEmpty && !stop.contains(w) && numberWords[w] == nil &&
            !w.hasPrefix("полтор") && !w.hasPrefix("косар") && !w.hasPrefix("пятихат") && !w.hasPrefix("тысяч")
        }
        let n = words.prefix(4).joined(separator: " ")
        guard let first = n.first else { return cat.name }
        return first.uppercased() + n.dropFirst()
    }
}
