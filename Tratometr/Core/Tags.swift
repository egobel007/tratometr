import Foundation
import SwiftUI

// MARK: - People ("с Ариной")

struct Person: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Other words that mean this person, e.g. "девушка"
    var aliases: [String] = []

    var stems: [String] {
        ([name] + aliases).map { Tags.nameStem($0) }.filter { $0.count >= 2 }
    }

    /// "С Ариной", "С Машей", "С друзьями"
    var withName: String { "С " + Tags.instrumental(name) }
}

/// What the user taught: a word stem always means this group / subcategory.
struct TagRule: Codable, Equatable {
    var kind: String   // expense | income
    var group: String
    var sub: String
}

struct CustomSub: Hashable {
    let key: String
    let name: String
}

/// Snapshot passed to the parsers.
struct TagContext {
    var people: [Person] = []
    var rules: [String: TagRule] = [:]
    var subs: [String: [String]] = [:]
    static let empty = TagContext()
}

/// People, learned rules and the user's own subcategories. Lives in UserDefaults.
final class TagStore: ObservableObject {
    static let shared = TagStore()

    @Published var people: [Person] { didSet { persist() } }
    @Published private(set) var rules: [String: TagRule] { didSet { persist() } }
    @Published private(set) var customSubs: [String: [String]] { didSet { persist() } }

    private init() {
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        people = load("tags_people", [Person]())
        rules = load("tags_rules", [String: TagRule]())
        customSubs = load("tags_subs", [String: [String]]())
        if !UserDefaults.standard.bool(forKey: "tags_seeded") {
            UserDefaults.standard.set(true, forKey: "tags_seeded")
            if people.isEmpty { people = [Person(name: "Арина", aliases: ["девушка"])] }
        }
    }

    private func persist() {
        let enc = JSONEncoder()
        if let d = try? enc.encode(people) { UserDefaults.standard.set(d, forKey: "tags_people") }
        if let d = try? enc.encode(rules) { UserDefaults.standard.set(d, forKey: "tags_rules") }
        if let d = try? enc.encode(customSubs) { UserDefaults.standard.set(d, forKey: "tags_subs") }
    }

    var context: TagContext {
        var subs: [String: [String]] = [:]
        for key in Set(Tags.seeds.keys).union(customSubs.keys) {
            subs[key] = Tags.uniq((Tags.seeds[key] ?? []).map(\.0) + (customSubs[key] ?? []))
        }
        return TagContext(people: people, rules: rules, subs: subs)
    }

    func subs(isIncome: Bool, group: String) -> [String] {
        let key = Tags.key(isIncome, group)
        return Tags.uniq((Tags.seeds[key] ?? []).map(\.0) + (customSubs[key] ?? []))
    }

    var allCustomSubs: [CustomSub] {
        customSubs.keys.sorted().flatMap { k in (customSubs[k] ?? []).map { CustomSub(key: k, name: $0) } }
    }

    var ruleCount: Int { rules.count }

    // MARK: changes

    @discardableResult
    func addPerson(_ raw: String) -> String? {
        let name = Tags.capitalized(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard name.count >= 2 else { return nil }
        if let existing = people.first(where: { $0.stems.contains(Tags.nameStem(name)) }) { return existing.name }
        people.append(Person(name: name))
        return name
    }

    func registerSub(isIncome: Bool, group: String, sub: String) {
        let s = sub.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !subs(isIncome: isIncome, group: group).contains(s) else { return }
        customSubs[Tags.key(isIncome, group), default: []].append(s)
    }

    func removeCustomSub(key: String, name: String) {
        customSubs[key]?.removeAll { $0 == name }
        rules = rules.filter { $0.value.sub != name }
    }

    func learn(note: String, isIncome: Bool, group: String, sub: String) {
        guard let stem = Tags.learnStem(note, people: people) else { return }
        rules[stem] = TagRule(kind: isIncome ? "income" : "expense", group: group, sub: sub)
    }

    func forgetRules() { rules = [:] }

    /// Called when a parsed record is saved.
    func remember(_ d: DraftExpense) {
        registerSub(isIncome: d.isIncome, group: d.groupID, sub: d.sub)
        for n in d.people { addPerson(n) }
        if d.edited { learn(note: d.note, isIncome: d.isIncome, group: d.groupID, sub: d.sub) }
    }
}

// MARK: - Helpers

enum Tags {
    static func key(_ isIncome: Bool, _ group: String) -> String { (isIncome ? "income:" : "expense:") + group }

    static func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "ё", with: "е") }

    static func words(_ s: String) -> [String] {
        norm(s).components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    static func stem5(_ w: String) -> String? { w.count >= 4 ? String(w.prefix(5)) : nil }

    /// A keyword is found when a word starts with it; phrases are looked up in the whole text.
    static func hits(_ k: String, tokens: [String], text: String) -> Bool {
        if k.contains(" ") || k.contains("-") { return text.contains(k) }
        if k.count <= 3 { return tokens.contains { $0.hasPrefix(k) && $0.count <= k.count + 3 } }
        return tokens.contains { $0.hasPrefix(k) }
    }

    /// Word start differs from the keyword by at most one letter: «ристоран» ≈ «ресторан»
    static func close(_ token: String, _ k: String) -> Bool {
        let t = Array(token), b = Array(k)
        for len in max(1, b.count - 1)...min(t.count, b.count + 1) {
            if distance(Array(t.prefix(len)), b) <= 1 { return true }
        }
        return false
    }

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    static func uniq(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    static func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    static func nameStem(_ name: String) -> String {
        let n = norm(name).trimmingCharacters(in: .whitespaces)
        guard n.count > 3, let last = n.last, "аяйьоеиыу".contains(last) else { return n }
        return String(n.dropLast())
    }

    static func matches(_ word: String, stem: String) -> Bool {
        word.hasPrefix(stem) && word.count <= stem.count + 3
    }

    static func isPersonWord(_ w: String, _ people: [Person]) -> Bool {
        let lw = norm(w).filter(\.isLetter)
        guard !lw.isEmpty else { return false }
        return people.contains { p in p.stems.contains { matches(lw, stem: $0) } }
    }

    // MARK: people in text

    static let relations: [(String, String)] = [
        ("мам", "Мама"), ("пап", "Папа"), ("брат", "Брат"), ("сестр", "Сестра"), ("друз", "Друзья"),
        ("коллег", "Коллеги"), ("бабушк", "Бабушка"), ("дедушк", "Дедушка"), ("сын", "Сын"),
        ("дочк", "Дочка"), ("дочер", "Дочка")
    ]

    private static let notNames = ["яндекс", "сбер", "тиньк", "альфа", "втб", "озон", "вайлд", "самокат", "лавк",
                                   "карт", "собой", "работ", "доставк", "скидк", "сдач", "налич", "кэш", "кеш"]

    /// Known people mentioned in a piece of text, plus new names after «с / со / для».
    static func detectPeople(_ chunk: String, _ ctx: TagContext) -> [String] {
        var out: [String] = []
        for p in ctx.people where mentions(p, in: chunk) { out.append(p.name) }
        for n in newPeople(in: chunk, known: ctx.people) where !out.contains(n) { out.append(n) }
        return out
    }

    static func mentions(_ p: Person, in text: String) -> Bool {
        let st = p.stems
        return words(text).contains { w in st.contains { matches(w, stem: $0) } }
    }

    static func newPeople(in chunk: String, known: [Person]) -> [String] {
        var out: [String] = []
        for g in chunk.allCaptureGroups(#"(?:^|[\s,(])(с|со|для|вместе с)\s+([A-Za-zА-Яа-яЁё]+)"#) where g.count >= 3 {
            let prep = norm(g[1])
            let w = g[2]
            let lw = norm(w)
            if known.contains(where: { p in p.stems.contains { matches(lw, stem: $0) } }) { continue }
            if let rel = relations.first(where: { lw.hasPrefix($0.0) && lw.count <= $0.0.count + 4 }) {
                if !out.contains(rel.1) { out.append(rel.1) }
                continue
            }
            guard prep != "для", w.first?.isUppercase == true, lw.count >= 4,
                  !notNames.contains(where: { lw.hasPrefix($0) }),
                  LocalParser.detectCategory(lw) == .other,
                  let nom = nominative(w) else { continue }
            if !out.contains(nom) { out.append(nom) }
        }
        return out
    }

    /// "Ариной" → "Арина", "Машей" → "Маша", "Иваном" → "Иван", "Андреем" → "Андрей"
    static func nominative(_ w: String) -> String? {
        let lw = norm(w)
        let hush = "жшчщц"
        let vowels = "аеиоуыэюя"
        if lw.hasSuffix("ой") { return String(w.dropLast(2)) + "а" }
        if lw.hasSuffix("ей") {
            let base = w.dropLast(2)
            guard let last = base.last.map({ Character($0.lowercased()) }) else { return nil }
            return String(base) + (hush.contains(last) ? "а" : "я")
        }
        if lw.hasSuffix("ом") { return String(w.dropLast(2)) }
        if lw.hasSuffix("ем") {
            let base = w.dropLast(2)
            guard let last = base.last.map({ Character($0.lowercased()) }) else { return nil }
            if vowels.contains(last) { return String(base) + "й" }
            if hush.contains(last) { return String(base) }
            return String(base) + "ь"
        }
        return nil
    }

    /// "Арина" → "Ариной"
    static func instrumental(_ name: String) -> String {
        let l = norm(name)
        guard let last = l.last else { return name }
        let prev = l.dropLast().last
        let hush = "жшчщц"
        switch last {
        case "а":
            return String(name.dropLast()) + ((prev.map { hush.contains($0) } ?? false) ? "ей" : "ой")
        case "я":
            return l.hasSuffix("ья") ? String(name.dropLast()) + "ями" : String(name.dropLast()) + "ей"
        case "й", "ь":
            return String(name.dropLast()) + "ем"
        case "и", "ы":
            return String(name.dropLast()) + "ами"
        case "о", "е", "у", "ю", "э":
            return name
        default:
            return name + (hush.contains(last) ? "ем" : "ом")
        }
    }

    /// Removes "с Ариной" from a note: "Кафе с Ариной" → "Кафе"
    static func stripPeople(_ note: String, people: [Person]) -> String {
        let preps: Set<String> = ["с", "со", "для", "вместе"]
        var out: [String] = []
        for token in note.components(separatedBy: .whitespaces) where !token.isEmpty {
            if isPersonWord(token, people) || relations.contains(where: { norm(token).hasPrefix($0.0) && norm(token).count <= $0.0.count + 4 }) {
                while let last = out.last, preps.contains(norm(last)) { out.removeLast() }
                continue
            }
            out.append(token)
        }
        while let last = out.last, preps.contains(norm(last)) { out.removeLast() }
        let result = out.joined(separator: " ")
        return result.isEmpty ? note : capitalized(result)
    }

    // MARK: subcategories

    /// Built-in precise subcategories per group, with the word stems that point to them.
    static let seeds: [String: [(String, [String])]] = [
        "expense:cafe": [
            ("Столовая", ["столов"]),
            ("Фастфуд", ["фастфуд", "макдон", "kfc", "кфс", "бургер", "шаурм", "шаверм", "вкусно и точка", "хот-дог", "хотдог", "донер"]),
            ("Ресторан", ["ресторан", "рестик"]),
            ("Доставка еды", ["доставк"]),
            ("Бар", ["бар", "пиво", "пива", "коктейл", "вино", "вина"]),
            ("Суши", ["суши", "ролл"]),
            ("Пицца", ["пицц"]),
            ("Кафе", ["кафе"])
        ],
        "expense:food": [
            ("Супермаркет", ["пятерочк", "перекрест", "магнит", "ашан", "лента", "вкусвилл", "дикси", "спар", "супермаркет", "albert", "jumbo", "lidl", "aldi"]),
            ("Доставка продуктов", ["лавк", "доставк"]),
            ("Рынок", ["рынок", "рынк"])
        ],
        "expense:coffee": [
            ("Кофе", ["кофе", "капуч", "латте", "раф", "американо", "эспрессо", "флэт"]),
            ("Выпечка", ["круассан", "булк", "пирож", "выпечк"]),
            ("Снеки", ["снек", "шоколад", "батончик", "чипс", "морожен"]),
            ("Напитки", ["вода", "воду", "сок", "энергетик", "чай"])
        ],
        "expense:transport": [
            ("Метро", ["метро"]),
            ("Автобус", ["автобус", "трамва", "троллейб"]),
            ("Поезд", ["электричк", "поезд"]),
            ("Бензин", ["бензин", "заправк", "топливо"]),
            ("Парковка", ["парковк"]),
            ("Каршеринг", ["каршеринг"]),
            ("Самокат", ["самокат"])
        ],
        "expense:home": [
            ("Аренда", ["аренд", "квартир"]),
            ("Коммуналка", ["коммунал", "жкх", "электричеств", "свет", "газ"]),
            ("Ремонт", ["ремонт"]),
            ("Бытовое", ["бытов", "хозтовар", "порошок", "уборк"])
        ],
        "expense:subs": [
            ("Связь", ["связь", "мобильн"]),
            ("Интернет", ["интернет"]),
            ("Подписки", ["подписк", "netflix", "spotify", "icloud", "youtube", "кинопоиск", "chatgpt", "claude"])
        ],
        "expense:health": [
            ("Аптека", ["аптек", "лекарств", "таблет", "витамин"]),
            ("Врач", ["врач", "доктор", "клиник", "больниц", "анализ"]),
            ("Стоматолог", ["стоматолог", "зуб"]),
            ("Массаж", ["массаж"])
        ],
        "expense:beauty": [
            ("Стрижка", ["стрижк", "барбер", "парикмах"]),
            ("Маникюр", ["маникюр", "педикюр"]),
            ("Косметика", ["космет", "крем", "шампун", "духи"])
        ],
        "expense:clothes": [
            ("Обувь", ["кроссовк", "обув", "ботинк", "туфл", "кед"])
        ],
        "expense:fun": [
            ("Кино", ["кино"]),
            ("Концерты", ["концерт", "театр"]),
            ("Игры", ["игр", "steam", "playstation"]),
            ("Клубы", ["клуб", "кальян"])
        ],
        "expense:shop": [
            ("Маркетплейсы", ["ozon", "озон", "wildberries", "вайлдберриз", "amazon", "амазон"]),
            ("Техника", ["техник", "наушник", "ноутбук", "зарядк", "чехол", "гаджет", "телефон"])
        ],
        "expense:travel": [
            ("Билеты", ["авиа", "самолет", "перелет", "билет"]),
            ("Жильё", ["отел", "гостиниц", "airbnb", "букинг", "booking", "хостел"])
        ],
        "expense:gifts": [
            ("Цветы", ["цвет", "букет"])
        ],
        "expense:sport": [
            ("Зал", ["спортзал", "фитнес", "трениров", "бассейн", "йог"]),
            ("Учёба", ["курс", "учеб", "урок", "репетитор"]),
            ("Книги", ["книг"])
        ],
        "income:salary": [
            ("Аванс", ["аванс"]),
            ("Премия", ["преми", "бонус"])
        ],
        "income:sale": [
            ("Перепродажа", ["перепрод"]),
            ("Авито", ["авито", "avito"])
        ],
        "income:side": [
            ("Фриланс", ["фриланс"])
        ],
        "income:refund": [
            ("Кэшбэк", ["кэшбэк", "кешбэк", "кешбек", "кэшбек", "cashback"]),
            ("Возврат", ["возврат"])
        ],
        "income:invest": [
            ("Проценты", ["процент", "вклад"]),
            ("Дивиденды", ["дивиденд"])
        ]
    ]

    static func seedSub(_ text: String, isIncome: Bool, group: String) -> String {
        let t = norm(text)
        let tokens = words(t)
        var best = ""
        var score = 0
        for (name, stems) in seeds[key(isIncome, group)] ?? [] {
            for s in stems where s.count > score && hits(s, tokens: tokens, text: t) {
                best = name
                score = s.count
            }
        }
        return best
    }

    /// One of the user's own subcategories whose first word appears in the text
    static func customSub(_ text: String, list: [String]) -> String {
        let ws = Set(words(text).compactMap(stem5))
        return list.first { name in
            guard let first = words(name).first, let st = stem5(first) else { return false }
            return ws.contains(st)
        } ?? ""
    }

    static func rule(for text: String, ctx: TagContext) -> TagRule? {
        for w in words(text) where !isPersonWord(w, ctx.people) {
            if let st = stem5(w), let r = ctx.rules[st] { return r }
        }
        return nil
    }

    static let learnSkip: Set<String> = ["потратил", "купил", "заплатил", "оплатил", "пришло", "получил", "часть", "вчера", "сегодня"]

    static func learnStem(_ note: String, people: [Person]) -> String? {
        for w in words(note) where w.count >= 4 && !learnSkip.contains(w) && !isPersonWord(w, people) {
            return stem5(w)
        }
        return nil
    }

    /// First word of a note as a new subcategory: "Корм коту" → "Корм"
    static func autoSub(note: String, groupName: String) -> String {
        guard note != groupName, let first = note.components(separatedBy: .whitespaces).first(where: { !$0.isEmpty }) else { return "" }
        let letters = first.filter { $0.isLetter || $0 == "-" }
        guard letters.count >= 3 else { return "" }
        return capitalized(letters)
    }

    /// Learned rules first, then built-in and own subcategories, then a brand new one for "Другое".
    static func applyRules(_ d: inout DraftExpense, text: String, ctx: TagContext, allowKindSwitch: Bool = true) {
        if let r = rule(for: text, ctx: ctx), allowKindSwitch || (r.kind == "income") == d.isIncome {
            if r.kind == "income" {
                d.isIncome = true
                d.income = IncomeSource(rawValue: r.group) ?? d.income
            } else {
                d.isIncome = false
                d.category = SpendCategory(rawValue: r.group) ?? d.category
            }
            if !r.sub.isEmpty { d.sub = r.sub }
            return
        }
        if d.sub.isEmpty { d.sub = seedSub(text, isIncome: d.isIncome, group: d.groupID) }
        if d.sub.isEmpty { d.sub = customSub(text, list: ctx.subs[key(d.isIncome, d.groupID)] ?? []) }
        let isOther = d.isIncome ? d.income == .other : d.category == .other
        if d.sub.isEmpty && isOther { d.sub = autoSub(note: d.note, groupName: d.kindName) }
    }

    /// Tidy up a record that came from Claude.
    static func finishClaude(_ d: inout DraftExpense, ctx: TagContext) {
        d.people = uniq(d.people.compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let st = nameStem(name)
            if let known = ctx.people.first(where: { p in p.stems.contains { matches(st, stem: $0) || st == $0 } }) { return known.name }
            return capitalized(name)
        })
        let everyone = ctx.people + d.people.map { Person(name: $0) }
        d.note = stripPeople(d.note, people: everyone)
        if !d.isIncome && d.category == .other {
            let local = LocalParser.detectCategory(d.note + " " + d.sub)
            if local != .other { d.category = local }
        }
        applyRules(&d, text: d.note + " " + d.sub, ctx: ctx)
    }
}
