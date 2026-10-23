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

    init(amount: Double, currency: String, categoryID: String, note: String, date: Date,
         source: String, rawText: String = "", kind: String = "expense") {
        self.uid = UUID()
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.note = note
        self.date = date
        self.source = source
        self.rawText = rawText
        self.kind = kind
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

    var symbol: String { isIncome ? income.symbol : category.symbol }
    var color: Color { isIncome ? income.color : category.color }
    var kindName: String { isIncome ? income.name : category.name }
}

extension SpendItem {
    init(_ e: Expense) {
        self.init(id: e.uid.uuidString, amount: e.amount, currency: e.currency,
                  category: e.isIncome ? .other : e.category, note: e.note, date: e.date,
                  source: e.source, isIncome: e.isIncome, income: e.incomeSource)
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

    var symbol: String { isIncome ? income.symbol : category.symbol }
    var color: Color { isIncome ? income.color : category.color }
    var kindName: String { isIncome ? income.name : category.name }
    var categoryID: String { isIncome ? income.rawValue : category.rawValue }
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
        case .food: return (0.40, 0.70, 0.78)
        case .cafe: return (0.06, 0.72, 0.98)
        case .coffee: return (0.075, 0.55, 0.78)
        case .transport: return (0.58, 0.68, 0.96)
        case .taxi: return (0.125, 0.85, 0.98)
        case .home: return (0.74, 0.52, 0.92)
        case .subs: return (0.52, 0.75, 0.86)
        case .health: return (0.99, 0.62, 0.97)
        case .beauty: return (0.91, 0.50, 0.97)
        case .clothes: return (0.66, 0.50, 0.94)
        case .fun: return (0.83, 0.52, 0.88)
        case .shop: return (0.60, 0.42, 0.82)
        case .travel: return (0.47, 0.72, 0.76)
        case .gifts: return (0.25, 0.62, 0.80)
        case .sport: return (0.14, 0.78, 0.90)
        case .other: return (0.70, 0.22, 0.74)
        }
    }

    var color: Color { Color(hue: hsb.0, saturation: hsb.1, brightness: hsb.2) }
    var rgb: SIMD3<Float> { rgbFrom(hsb) }

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
        case .food: return ["продукт", "магазин", "супермаркет", "пятерочк", "перекрест", "магнит", "ашан", "лента", "вкусвилл", "дикси", "спар", "молок", "хлеб", "овощ", "фрукт", "мясо", "куриц", "яйц", "сыр", "albert", "jumbo", "lidl", "aldi", "рынок"]
        case .cafe: return ["кафе", "ресторан", "обед", "ужин", "завтрак", "бар", "пицц", "суши", "ролл", "бургер", "доставк", "шаурм", "макдон", "kfc", "вкусно и точка", "столов", "пиво", "вино", "коктейл"]
        case .coffee: return ["кофе", "капуч", "латте", "раф", "американо", "эспрессо", "флэт", "чай", "перекус", "булк", "круассан", "пирож", "снек", "шоколад", "вода", "сок", "энергетик", "морожен"]
        case .transport: return ["метро", "автобус", "трамва", "троллейб", "электричк", "поезд", "бензин", "заправк", "топливо", "парковк", "проезд", "транспорт", "каршеринг", "самокат", "мойк"]
        case .taxi: return ["такси", "убер", "uber", "bolt", "болт", "яндекс го"]
        case .home: return ["квартир", "аренд", "жкх", "коммунал", "электричеств", "газ", "ремонт", "мебел", "икеа", "ikea", "бытов", "хозтовар", "уборк", "порошок", "посуд"]
        case .subs: return ["связь", "мобильн", "интернет", "подписк", "netflix", "spotify", "icloud", "youtube", "кинопоиск", "chatgpt", "claude"]
        case .health: return ["аптек", "лекарств", "врач", "доктор", "анализ", "стоматолог", "зуб", "клиник", "витамин", "таблет", "больниц", "массаж"]
        case .beauty: return ["стрижк", "барбер", "парикмах", "маникюр", "педикюр", "космет", "крем", "шампун", "салон", "бритв", "духи"]
        case .clothes: return ["одежд", "кроссовк", "обув", "куртк", "джинс", "футболк", "рубаш", "плать", "носк", "кофт", "шапк", "zara", "uniqlo"]
        case .fun: return ["кино", "концерт", "театр", "игр", "клуб", "музей", "выставк", "развлеч", "боулинг", "кальян", "steam", "playstation", "квест"]
        case .shop: return ["техник", "наушник", "ноутбук", "зарядк", "чехол", "ozon", "озон", "wildberries", "вайлдберриз", "amazon", "амазон", "гаджет"]
        case .travel: return ["отел", "гостиниц", "авиа", "самолет", "перелет", "путешеств", "airbnb", "букинг", "booking", "тур", "виза", "хостел"]
        case .gifts: return ["подар", "цвет", "букет", "день рожд", "открытк"]
        case .sport: return ["спортзал", "фитнес", "трениров", "бассейн", "йог", "курс", "книг", "учеб", "урок", "репетитор"]
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
        case .salary: return (0.42, 0.72, 0.80)
        case .side: return (0.50, 0.72, 0.84)
        case .sale: return (0.13, 0.80, 0.96)
        case .transfer: return (0.90, 0.48, 0.96)
        case .refund: return (0.56, 0.62, 0.95)
        case .invest: return (0.30, 0.66, 0.78)
        case .other: return (0.72, 0.38, 0.88)
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
