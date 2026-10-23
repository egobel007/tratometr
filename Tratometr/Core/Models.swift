import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - Stored expense

@Model
final class Expense {
    var uid: UUID = UUID()
    var amount: Double = 0
    var currency: String = "RUB"
    var categoryID: String = "other"
    var note: String = ""
    var date: Date = Date()
    var source: String = "voice"   // voice | photo | text
    var rawText: String = ""

    init(amount: Double, currency: String, categoryID: String, note: String, date: Date, source: String, rawText: String = "") {
        self.uid = UUID()
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.note = note
        self.date = date
        self.source = source
        self.rawText = rawText
    }

    var category: SpendCategory { SpendCategory(rawValue: categoryID) ?? .other }
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
}

extension SpendItem {
    init(_ e: Expense) {
        self.init(id: e.uid.uuidString, amount: e.amount, currency: e.currency,
                  category: e.category, note: e.note, date: e.date, source: e.source)
    }
}

// MARK: - A parsed but not yet saved expense

struct DraftExpense: Identifiable, Equatable {
    var id = UUID()
    var amount: Double
    var currency: String
    var category: SpendCategory
    var note: String
    var date: Date
    var source: String
    var raw: String
}

// MARK: - Categories

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

    /// hue, saturation, brightness
    private var hsb: (Double, Double, Double) {
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

    var rgb: SIMD3<Float> {
        let c = UIColor(hue: CGFloat(hsb.0), saturation: CGFloat(hsb.1), brightness: CGFloat(hsb.2), alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }

    /// Examples for Claude's prompt
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
