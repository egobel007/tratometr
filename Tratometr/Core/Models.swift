import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - Stored record (an expense or an income)

@Model
final class Expense {
    var uid: UUID = UUID()
    var amount: Double = 0
    var currency: String = "RUB"
    /// SpendCategory id for expenses, IncomeSource id for incomes
    var categoryID: String = "other"
    var note: String = ""
    var date: Date = Date()
    var source: String = "voice"   // voice | photo | text
    var rawText: String = ""
    var kind: String = "expense"   // expense | income
    /// Precise subcategory, e.g. "Столовая", "Перепродажа"
    var subcategory: String = ""
    /// Who it was with, comma separated: "Арина,Маша"
    var people: String = ""

    init(amount: Double, currency: String, categoryID: String, note: String, date: Date,
         source: String, rawText: String = "", kind: String = "expense",
         subcategory: String = "", people: String = "") {
        self.uid = UUID()
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.note = note
        self.date = date
        self.source = source
        self.rawText = rawText
        self.kind = kind
        self.subcategory = subcategory
        self.people = people
    }

    var peopleList: [String] {
        people.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var isIncome: Bool { kind == "income" }
    var category: SpendCategory { SpendCategory(rawValue: categoryID) ?? .other }
    var incomeSource: IncomeSource { IncomeSource(rawValue: categoryID) ?? .other }
}

// MARK: - Lightweight value used by screens (real data and the demo share it)

struct SpendItem: Identifiable, Hashable {
    let id: String
    let amount: Double
    let currency: String
    let category: SpendCategory
    let note: String
    let date: Date
    let source: String
    var isIncome: Bool = false
    var income: IncomeSource = .other
    var sub: String = ""
    var people: [String] = []

    var symbol: String { isIncome ? income.symbol : category.symbol }
    var color: Color { isIncome ? income.color : category.color }
    var kindName: String { isIncome ? income.name : category.name }
    /// Subcategory if there is one, otherwise the group
    var detailName: String { sub.isEmpty ? kindName : sub }
}

extension SpendItem {
    init(_ e: Expense) {
        self.init(id: e.uid.uuidString, amount: e.amount, currency: e.currency,
                  category: e.isIncome ? .other : e.category, note: e.note, date: e.date,
                  source: e.source, isIncome: e.isIncome, income: e.incomeSource,
                  sub: e.subcategory, people: e.peopleList)
    }
}

// MARK: - A parsed but not yet saved record

struct DraftExpense: Identifiable, Equatable {
    var id = UUID()
    var amount: Double
    var currency: String
    var category: SpendCategory
    var note: String
    var date: Date
    var source: String
    var raw: String
    var isIncome: Bool = false
    var income: IncomeSource = .other
    var sub: String = ""
    var people: [String] = []
    /// The user changed the type, group or subcategory by hand: learn from it
    var edited = false

    var symbol: String { isIncome ? income.symbol : category.symbol }
    var color: Color { isIncome ? income.color : category.color }
    var kindName: String { isIncome ? income.name : category.name }
    var categoryID: String { isIncome ? income.rawValue : category.rawValue }
    var groupID: String { categoryID }
}

// MARK: - Expense categories

enum SpendCategory: String, CaseIterable, Identifiable, Codable {
    case food, cafe, coffee, transport, taxi, home, subs, health, beauty, clothes, fun, shop, travel, gifts, sport, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .food: return "Продукты"
        case .cafe: return "Кафе и рестораны"
        case .coffee: return "Кофе и перекусы"
        case .transport: return "Транспорт"
        case .taxi: return "Такси"
        case .home: return "Дом и ЖКХ"
        case .subs: return "Связь и подписки"
        case .health: return "Здоровье"
        case .beauty: return "Красота и уход"
        case .clothes: return "Одежда"
        case .fun: return "Развлечения"
        case .shop: return "Покупки и техника"
        case .travel: return "Путешествия"
        case .gifts: return "Подарки"
        case .sport: return "Спорт и учёба"
        case .other: return "Другое"
        }
    }

    var symbol: String {
        switch self {
        case .food: return "basket.fill"
        case .cafe: return "fork.knife"
        case .coffee: return "cup.and.saucer.fill"
        case .transport: return "tram.fill"
        case .taxi: return "car.fill"
        case .home: return "house.fill"
        case .subs: return "iphone"
        case .health: return "cross.case.fill"
        case .beauty: return "sparkles"
        case .clothes: return "tshirt.fill"
        case .fun: return "ticket.fill"
        case .shop: return "bag.fill"
        case .travel: return "airplane"
        case .gifts: return "gift.fill"
        case .sport: return "figure.run"
        case .other: return "ellipsis.circle.fill"
        }
    }

    /// hue, saturation, brightness (bright and friendly, readable under a white symbol)
    fileprivate var hsb: (Double, Double, Double) {
        switch self {
        case .food: return (0.40, 0.68, 0.67)
        case .cafe: return (0.072, 0.75, 0.93)
        case .coffee: return (0.056, 0.55, 0.66)
        case .transport: return (0.583, 0.70, 0.86)
        case .taxi: return (0.122, 0.88, 0.92)
        case .home: return (0.736, 0.50, 0.82)
        case .subs: return (0.528, 0.80, 0.74)
        case .health: return (0.006, 0.66, 0.88)
        case .beauty: return (0.917, 0.52, 0.90)
        case .clothes: return (0.647, 0.50, 0.82)
        case .fun: return (0.828, 0.50, 0.78)
        case .shop: return (0.605, 0.25, 0.62)
        case .travel: return (0.472, 0.75, 0.64)
        case .gifts: return (0.239, 0.62, 0.68)
        case .sport: return (0.144, 0.75, 0.74)
        case .other: return (0.61, 0.10, 0.66)
        }
    }

    var color: Color { Color(hue: hsb.0, saturation: hsb.1, brightness: hsb.2) }
    var rgb: SIMD3<Float> { rgbFrom(hsb) }

    /// Related shades for subcategories of the same group
    func color(variant v: Int) -> Color {
        guard v > 0 else { return color }
        let h = (hsb.0 + Double(v) * 0.045).truncatingRemainder(dividingBy: 1)
        let s = max(0.3, hsb.1 - 0.12 * Double(v % 3))
        let b = min(1, max(0.5, hsb.2 + (v % 2 == 0 ? -0.1 : 0.04)))
        return Color(hue: h, saturation: s, brightness: b)
    }

    var hint: String {
        switch self {
        case .food: return "супермаркет, магазин, продукты"
        case .cafe: return "обед, ужин, доставка еды, бар"
        case .coffee: return "кофе, чай, выпечка, снеки"
        case .transport: return "метро, автобус, поезд, бензин, парковка"
        case .taxi: return "такси, Uber, Bolt"
        case .home: return "аренда, коммуналка, ремонт, быт"
        case .subs: return "телефон, интернет, подписки"
        case .health: return "аптека, врач, анализы"
        case .beauty: return "стрижка, маникюр, косметика"
        case .clothes: return "одежда, обувь"
        case .fun: return "кино, концерты, игры, хобби"
        case .shop: return "маркетплейсы, техника, гаджеты"
        case .travel: return "билеты, отели, поездки"
        case .gifts: return "подарки, цветы"
        case .sport: return "зал, тренировки, курсы, книги"
        case .other: return "всё остальное"
        }
    }

    /// Stems for the offline parser (lowercase, ё → е)
    var keywords: [String] {
        switch self {
        case .food: return ["продукт", "магазин", "супермаркет", "гипермаркет", "пятерочк", "перекрест", "магнит", "ашан", "лента", "ленту", "вкусвилл", "дикси", "спар", "окей", "азбук", "глобус", "светофор", "сбермаркет", "купер", "лавк", "закупк", "молок", "хлеб", "овощ", "фрукт", "мясо", "мяса", "куриц", "яйц", "сыр", "колбас", "круп", "макарон", "йогурт", "клубник", "albert", "jumbo", "lidl", "aldi", "рынок", "рынк", "еда домой"]
        case .cafe: return ["кафе", "кафешк", "ресторан", "рестик", "обед", "пообедал", "ужин", "поужинал", "завтрак", "позавтракал", "бранч", "ланч", "бар", "паб", "пиво", "пива", "вино", "вина", "коктейл", "пицц", "суши", "ролл", "бургер", "доставк", "шаурм", "шаверм", "фастфуд", "хот-дог", "хотдог", "донер", "макдон", "макдак", "kfc", "кфс", "ростикс", "вкусно и точка", "бургер кинг", "теремок", "додо", "столов", "поел", "поели", "еду"]
        case .coffee: return ["кофе", "кофейн", "капуч", "латте", "раф", "американо", "эспрессо", "флэт", "флет", "какао", "чай", "перекус", "булк", "булочк", "круассан", "пирож", "выпечк", "снек", "шоколад", "батончик", "чипс", "вода", "воду", "сок", "энергетик", "морожен", "конфет", "сладост"]
        case .transport: return ["метро", "автобус", "трамва", "троллейб", "электричк", "поезд", "проезд", "тройк", "транспорт", "бензин", "заправк", "топливо", "дизел", "парковк", "каршеринг", "делимобил", "ситидрайв", "самокат", "whoosh", "вуш", "мойк", "шиномонтаж", "автосервис"]
        case .taxi: return ["такси", "таксист", "убер", "uber", "bolt", "болт", "яндекс го", "ситимобил", "gett"]
        case .home: return ["квартир", "аренд", "жкх", "коммунал", "квартплат", "электричеств", "газ", "ремонт", "мебел", "икеа", "ikea", "hoff", "бытов", "хозтовар", "порошок", "уборк", "клининг", "посуд", "леруа", "обои", "сантехник"]
        case .subs: return ["связь", "мобильн", "сотов", "интернет", "подписк", "netflix", "spotify", "icloud", "youtube", "ютуб", "кинопоиск", "okko", "окко", "иви", "яндекс плюс", "chatgpt", "claude", "впн", "vpn"]
        case .health: return ["аптек", "лекарств", "врач", "доктор", "анализ", "стоматолог", "зуб", "клиник", "витамин", "таблет", "больниц", "массаж", "терапевт", "узи", "мрт", "медцентр", "линз"]
        case .beauty: return ["стрижк", "подстриг", "барбер", "парикмах", "маникюр", "педикюр", "космет", "крем", "шампун", "салон", "бритв", "духи", "парфюм", "летуал", "золотое яблоко", "бров", "ресниц"]
        case .clothes: return ["одежд", "кроссовк", "обув", "ботинк", "туфл", "кед", "куртк", "пуховик", "пальто", "джинс", "брюк", "футболк", "рубаш", "плать", "юбк", "носк", "кофт", "свитер", "худи", "шапк", "шарф", "перчатк", "zara", "uniqlo", "ламод", "lamoda"]
        case .fun: return ["кино", "концерт", "театр", "игр", "клуб", "музей", "выставк", "развлеч", "боулинг", "кальян", "steam", "playstation", "квест", "караоке", "бильярд", "стендап", "вечеринк"]
        case .shop: return ["техник", "наушник", "ноутбук", "зарядк", "чехол", "гаджет", "ozon", "озон", "wildberries", "вайлдберриз", "вб", "amazon", "амазон", "алиэкспресс", "aliexpress", "днс", "мвидео", "эльдорадо", "яндекс маркет", "фикс прайс"]
        case .travel: return ["отел", "гостиниц", "авиа", "самолет", "перелет", "путешеств", "airbnb", "букинг", "booking", "тур", "виза", "хостел", "аэроэкспресс", "багаж", "отпуск", "поездк"]
        case .gifts: return ["подар", "цвет", "букет", "день рожд", "открытк", "сувенир"]
        case .sport: return ["спортзал", "зал", "фитнес", "трениров", "бассейн", "йог", "абонемент", "курс", "книг", "учеб", "урок", "репетитор", "протеин"]
        case .other: return []
        }
    }
}

// MARK: - Income sources

enum IncomeSource: String, CaseIterable, Identifiable, Codable {
    case salary, side, sale, transfer, refund, invest, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .salary: return "Зарплата"
        case .side: return "Подработка"
        case .sale: return "Продажи"
        case .transfer: return "Переводы и подарки"
        case .refund: return "Возвраты и кэшбэк"
        case .invest: return "Проценты и инвестиции"
        case .other: return "Другое"
        }
    }

    var symbol: String {
        switch self {
        case .salary: return "briefcase.fill"
        case .side: return "hammer.fill"
        case .sale: return "tag.fill"
        case .transfer: return "person.2.fill"
        case .refund: return "arrow.uturn.backward"
        case .invest: return "chart.line.uptrend.xyaxis"
        case .other: return "plus"
        }
    }

    fileprivate var hsb: (Double, Double, Double) {
        switch self {
        case .salary: return (0.42, 0.62, 0.64)
        case .side: return (0.50, 0.62, 0.70)
        case .sale: return (0.11, 0.70, 0.86)
        case .transfer: return (0.90, 0.42, 0.85)
        case .refund: return (0.56, 0.55, 0.80)
        case .invest: return (0.30, 0.55, 0.60)
        case .other: return (0.62, 0.12, 0.66)
        }
    }

    var color: Color { Color(hue: hsb.0, saturation: hsb.1, brightness: hsb.2) }
    var rgb: SIMD3<Float> { rgbFrom(hsb) }

    var hint: String {
        switch self {
        case .salary: return "зарплата, часть зарплаты, аванс, премия"
        case .side: return "подработка, фриланс, заказ, гонорар"
        case .sale: return "продал, перепродал, Авито"
        case .transfer: return "перевели, подарили, вернули долг"
        case .refund: return "возврат за покупку, кэшбэк"
        case .invest: return "проценты по вкладу, дивиденды"
        case .other: return "любые другие поступления"
        }
    }

    var keywords: [String] {
        switch self {
        case .salary: return ["зарплат", "аванс", "получк", "оклад", "преми", "бонус", "зп"]
        case .side: return ["подработ", "фриланс", "заказ", "гонорар", "шабашк", "халтур"]
        case .sale: return ["продал", "перепродал", "продаж", "авито", "avito", "толкнул"]
        case .transfer: return ["перевел", "перевели", "подарил", "скинул", "скинули", "вернул долг", "вернули долг"]
        case .refund: return ["возврат", "вернули деньги", "кэшбэк", "кешбэк", "кешбек", "кэшбек", "cashback"]
        case .invest: return ["процент", "дивиденд", "вклад", "инвест", "купон"]
        case .other: return []
        }
    }
}

private func rgbFrom(_ hsb: (Double, Double, Double)) -> SIMD3<Float> {
    let c = UIColor(hue: CGFloat(hsb.0), saturation: CGFloat(hsb.1), brightness: CGFloat(hsb.2), alpha: 1)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return SIMD3<Float>(Float(r), Float(g), Float(b))
}

// MARK: - Currencies

struct CurrencyInfo: Identifiable {
    let code: String
    let symbol: String
    let decimals: Int
    /// what counts as a "small purchase" in this currency
    let small: Double
    /// multiplier for demo numbers (they are written in roubles)
    let demo: Double
    let step: Double
    var id: String { code }

    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "RUB", symbol: "₽", decimals: 0, small: 500, demo: 1, step: 10),
        CurrencyInfo(code: "EUR", symbol: "€", decimals: 2, small: 6, demo: 0.011, step: 0.1),
        CurrencyInfo(code: "USD", symbol: "$", decimals: 2, small: 7, demo: 0.012, step: 0.1),
        CurrencyInfo(code: "KZT", symbol: "₸", decimals: 0, small: 2500, demo: 5.6, step: 50),
        CurrencyInfo(code: "GBP", symbol: "£", decimals: 2, small: 5, demo: 0.0095, step: 0.1)
    ]

    static func get(_ code: String) -> CurrencyInfo {
        all.first { $0.code == code } ?? CurrencyInfo(code: code, symbol: code, decimals: 2, small: 5, demo: 0.01, step: 0.1)
    }
}

enum Keys {
    static let claude = "claude_api_key"
}
