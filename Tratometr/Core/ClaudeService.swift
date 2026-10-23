import Foundation
import UIKit

enum ClaudeError: LocalizedError {
    case badKey
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badKey: return "Ключ Claude не подошёл. Проверь его в настройках."
        case .http(let code, let msg): return "Claude ответил ошибкой \(code): \(msg)"
        case .empty: return "Claude ничего не ответил."
        }
    }
}

/// Optional: talks to the Claude API with the user's own key.
struct ClaudeService {
    let apiKey: String

    static let fastModel = "claude-haiku-5-5"
    static let smartModel = "claude-sonnet-5-5"

    static var stored: ClaudeService? {
        guard let key = Keychain.load(Keys.claude) else { return nil }
        return ClaudeService(apiKey: key)
    }

    func send(_ prompt: String, image: UIImage? = nil, model: String, maxTokens: Int = 1024) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        var content: [[String: Any]] = []
        if let image, let jpeg = image.resized(maxSide: 1568).jpegData(compressionQuality: 0.8) {
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        content.append(["type": "text", "text": prompt])
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens,
                                   "messages": [["role": "user", "content": content]]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            if status == 401 || status == 403 { throw ClaudeError.badKey }
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw ClaudeError.http(status, msg)
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.isEmpty else { throw ClaudeError.empty }
        return text
    }

    private static var categoryList: String {
        SpendCategory.allCases.map { "\($0.rawValue): \($0.name) (\($0.hint))" }.joined(separator: "\n")
    }

    private static var incomeList: String {
        IncomeSource.allCases.map { "\($0.rawValue): \($0.name) (\($0.hint))" }.joined(separator: "\n")
    }

    func parseExpenses(text: String, currency: String, forceIncome: Bool = false) async throws -> [DraftExpense] {
        let prompt = """
        Разбери голосовую заметку о деньгах: траты и поступления. Текст продиктован голосом на русском: возможны ошибки распознавания, слова-паразиты, числа словами.
        Сегодня \(RuDate.longToday()). Основная валюта: \(currency).\(forceIncome ? " Человек сейчас записывает поступления, поэтому всё считай поступлениями, если явно не сказано иное." : "")

        Категории трат (id: название, примеры):
        \(Self.categoryList)

        Категории поступлений (id: название, примеры):
        \(Self.incomeList)

        Правила:
        - Каждая отдельная покупка это отдельный объект. Если одна сумма названа за несколько вещей, это одна трата.
        - «2 кофе по 250» это одна трата на 500.
        - Числа словами переводи в цифры: «полторы тысячи» = 1500, «две с половиной тысячи» = 2500, «косарь» = 1000, «пятихатка» = 500, «2к» = 2000.
        - daysAgo: 0 сегодня, 1 вчера, 2 позавчера; «в понедельник» = сколько дней назад был ближайший прошедший понедельник.
        - currency: ISO-код (RUB, EUR, USD, KZT, GBP). Если валюта не названа, ставь \(currency).
        - type: "expense" для трат, "income" для поступлений денег (пришло, получил, зарплата, аванс, продал, перевели мне, вернули, кэшбэк).
        - category: один id. Для трат из категорий трат (магазин продуктов вроде Пятёрочки или Lidl это food), для поступлений из категорий поступлений («часть зарплаты» это salary).
        - note: 1-4 слова по-русски с заглавной буквы: что купил или где («Капучино», «Такси до офиса»), для поступлений что пришло («Часть зарплаты», «Продал велосипед»).
        - Если сумм нет совсем, верни [].

        Ответь только JSON-массивом, без пояснений. Пример: [{"type":"expense","amount":250,"currency":"\(currency)","category":"coffee","note":"Капучино","daysAgo":0},{"type":"income","amount":40000,"currency":"\(currency)","category":"salary","note":"Часть зарплаты","daysAgo":0}]

        Текст: «\(text.prefix(2000))»
        """
        let reply = try await send(prompt, model: Self.fastModel, maxTokens: 800)
        return Self.drafts(from: reply, source: "voice", raw: text, currency: currency)
    }

    func parseReceipt(_ image: UIImage, currency: String) async throws -> [DraftExpense] {
        let prompt = """
        На фото чек или квитанция об оплате. Сегодня \(RuDate.longToday()). Основная валюта: \(currency).

        Категории (id: название, примеры):
        \(Self.categoryList)

        Найди итоговую сумму чека. Если в чеке товары разных категорий (например, продукты и бытовая химия), раздели итог по категориям так, чтобы суммы в сумме давали итог. Если всё одной категории, верни один объект.
        note: 1-4 слова по-русски: название магазина или что куплено.
        daysAgo: сколько дней назад дата на чеке (0, если сегодня или даты нет).
        currency: ISO-код валюты чека.
        Ответь только JSON-массивом: [{"amount":1234.5,"currency":"\(currency)","category":"food","note":"Пятёрочка","daysAgo":0}]
        Если это не чек и сумм нет, верни [].
        """
        let reply = try await send(prompt, image: image, model: Self.smartModel, maxTokens: 800)
        return Self.drafts(from: reply, source: "photo", raw: "фото чека", currency: currency)
    }

    func advice(_ summary: String) async throws -> String {
        let prompt = """
        Ты спокойный финансовый помощник. Вот траты человека:
        \(summary)

        Дай короткий разбор по-русски, 3-5 пунктов, каждый 1-2 предложения, с конкретными цифрами из данных: где проще всего сэкономить и примерно сколько, что в норме, где можно позволить себе тратить больше без вреда. Обращайся на «ты». Без вступления и выводов, без длинных тире, без markdown. Каждый пункт с новой строки и начинается с «• ».
        """
        return try await send(prompt, model: Self.smartModel, maxTokens: 900)
    }

    static func drafts(from reply: String, source: String, raw: String, currency: String) -> [DraftExpense] {
        guard let s = reply.firstIndex(of: "["), let e = reply.lastIndex(of: "]"), s < e,
              let data = String(reply[s...e]).data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return arr.compactMap { o in
            var amount: Double = 0
            if let n = o["amount"] as? NSNumber { amount = n.doubleValue }
            else if let s = o["amount"] as? String { amount = Money.parse(s) }
            amount = abs(amount)
            guard amount > 0, amount.isFinite else { return nil }
            var cur = (o["currency"] as? String)?.uppercased() ?? currency
            if !CurrencyInfo.all.contains(where: { $0.code == cur }) { cur = currency }
            let catID = (o["category"] as? String) ?? ""
            let isIncome = (o["type"] as? String) == "income" || (SpendCategory(rawValue: catID) == nil && IncomeSource(rawValue: catID) != nil)
            let cat = SpendCategory(rawValue: catID) ?? .other
            let src = IncomeSource(rawValue: catID) ?? .other
            var days = (o["daysAgo"] as? NSNumber)?.intValue ?? 0
            if days < 0 || days > 400 { days = 0 }
            let note = ((o["note"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            return DraftExpense(amount: (amount * 100).rounded() / 100, currency: cur, category: isIncome ? .other : cat,
                                note: note.isEmpty ? (isIncome ? src.name : cat.name) : String(note.prefix(60)),
                                date: RuDate.date(daysAgo: days), source: source, raw: raw,
                                isIncome: isIncome, income: src)
        }
    }
}

/// Picks Claude when a key is set, otherwise the offline parser / OCR.
enum ExpenseParser {
    static func parse(text: String, currency: String, forceIncome: Bool = false) async -> (items: [DraftExpense], notice: String?) {
        if let claude = ClaudeService.stored {
            do {
                let items = try await claude.parseExpenses(text: text, currency: currency, forceIncome: forceIncome)
                if !items.isEmpty { return (items, nil) }
            } catch {
                return (LocalParser.parse(text, currency: currency, forceIncome: forceIncome), "Claude не ответил, разобрал сам")
            }
        }
        return (LocalParser.parse(text, currency: currency, forceIncome: forceIncome), nil)
    }

    static func parseReceipt(_ image: UIImage, currency: String) async -> (items: [DraftExpense], notice: String?) {
        var notice: String? = nil
        if let claude = ClaudeService.stored {
            do {
                let items = try await claude.parseReceipt(image, currency: currency)
                if !items.isEmpty { return (items, nil) }
            } catch {
                notice = "Claude не ответил, прочитал чек сам"
            }
        }
        let lines = await ReceiptOCR.recognize(image)
        return (ReceiptOCR.extract(lines: lines, currency: currency), notice)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let side = max(size.width, size.height)
        guard side > maxSide else { return self }
        let k = maxSide / side
        let newSize = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
