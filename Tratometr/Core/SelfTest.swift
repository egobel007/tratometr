#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Runs in the iOS simulator on every cloud build: `simctl launch … -selftest`.
/// Prints one line per check and exits with 1 if anything is wrong.
enum SelfTest {
    struct Case {
        let text: String
        var count = 1
        var income = false
        let group: String
        var sub: String? = nil
        var amount: Double? = nil
        var person: String? = nil
        var yesterday = false
    }

    static let cases: [Case] = [
        Case(text: "ресторан 1500", group: "cafe", sub: "Ресторан", amount: 1500),
        Case(text: "1500 на ресторан", group: "cafe", sub: "Ресторан", amount: 1500),
        Case(text: "в ресторане полторы тысячи", group: "cafe", amount: 1500),
        Case(text: "ристоран 2000", group: "cafe", amount: 2000),
        Case(text: "Пятёрочка 1200", group: "food", sub: "Супермаркет", amount: 1200),
        Case(text: "продукты 2300", group: "food", amount: 2300),
        Case(text: "купил продукты в магните на 2 300", group: "food", amount: 2300),
        Case(text: "супермаркет 1800", group: "food", sub: "Супермаркет"),
        Case(text: "кофе 250", group: "coffee", sub: "Кофе", amount: 250),
        Case(text: "капучино 280 и круассан 190", count: 2, group: "coffee", amount: 280),
        Case(text: "такси 640", group: "taxi", amount: 640),
        Case(text: "метро 62", group: "transport", sub: "Метро"),
        Case(text: "бензин 3к", group: "transport", sub: "Бензин", amount: 3000),
        Case(text: "аптека 450", group: "health", sub: "Аптека"),
        Case(text: "обед в столовой 350", group: "cafe", sub: "Столовая", amount: 350),
        Case(text: "макдак 450", group: "cafe", sub: "Фастфуд"),
        Case(text: "оплатил интернет 600", group: "subs", sub: "Интернет"),
        Case(text: "мобильная связь 500", group: "subs", sub: "Связь"),
        Case(text: "подписка на музыку 299", group: "subs", sub: "Подписки"),
        Case(text: "наушники 4990", group: "shop", sub: "Техника"),
        Case(text: "озон 1200", group: "shop", sub: "Маркетплейсы"),
        Case(text: "кроссовки 7000", group: "clothes", sub: "Обувь"),
        Case(text: "стрижка 1500", group: "beauty", sub: "Стрижка"),
        Case(text: "кино с Ариной 900", group: "fun", sub: "Кино", person: "Арина"),
        Case(text: "ужин с Ариной в ресторане 3200", group: "cafe", amount: 3200, person: "Арина"),
        Case(text: "продукты с девушкой 2000", group: "food", person: "Арина"),
        Case(text: "аренда квартиры 45000", group: "home", sub: "Аренда"),
        Case(text: "коммуналка 5200", group: "home", sub: "Коммуналка"),
        Case(text: "вчера такси 400", group: "taxi", yesterday: true),
        Case(text: "полторы тысячи на продукты", group: "food", amount: 1500),
        Case(text: "1.500 ресторан", group: "cafe", amount: 1500),
        Case(text: "штраф 500", group: "other"),
        Case(text: "корм для кота 800", group: "other"),
        Case(text: "пришло 40000 часть зарплаты", income: true, group: "salary", amount: 40000),
        Case(text: "перепродал кроссовки за 12 тысяч", income: true, group: "sale", sub: "Перепродажа", amount: 12000),
        Case(text: "кэшбэк 1200", income: true, group: "refund"),
    ]

    @MainActor
    static func run() -> Never {
        var total = 0
        var failed = 0
        func check(_ ok: Bool, _ label: String) {
            total += 1
            if !ok { failed += 1 }
            print((ok ? "ok    " : "FAIL  ") + label)
        }

        let ctx = TagStore.shared.context
        for c in cases {
            let items = LocalParser.parse(c.text, currency: "RUB", ctx: ctx)
            guard let d = items.first else { check(false, "«\(c.text)»: ничего не разобрано"); continue }
            var problems: [String] = []
            if items.count != c.count { problems.append("записей \(items.count), ждал \(c.count)") }
            if d.isIncome != c.income { problems.append(d.isIncome ? "стал доходом" : "стал тратой") }
            if d.groupID != c.group { problems.append("категория \(d.groupID), ждал \(c.group)") }
            if let s = c.sub, d.sub != s { problems.append("уточнение «\(d.sub)», ждал «\(s)»") }
            if let a = c.amount, abs(d.amount - a) > 0.01 { problems.append("сумма \(d.amount), ждал \(a)") }
            if let p = c.person, !d.people.contains(p) { problems.append("нет отметки \(p)") }
            if c.person == nil && !d.people.isEmpty { problems.append("лишняя отметка \(d.people)") }
            if c.yesterday && !RuDate.cal.isDateInYesterday(d.date) { problems.append("не вчера") }
            check(problems.isEmpty, "«\(c.text)» → \(d.groupID)/\(d.sub) \(d.amount)" + (problems.isEmpty ? "" : "  [" + problems.joined(separator: "; ") + "]"))
        }

        // labels that used to be saved inside «Другое»
        check(Tags.group(forLabel: "Супермаркет")?.group == "food", "метка Супермаркет → Продукты")
        check(Tags.group(forLabel: "Связь")?.group == "subs", "метка Связь → Связь и подписки")
        check(Tags.group(forLabel: "Подписки")?.group == "subs", "метка Подписки → Связь и подписки")
        check(Tags.group(forLabel: "Покупки")?.group == "shop", "метка Покупки → Покупки и техника")
        check(Tags.group(forLabel: "Корм") == nil, "метка Корм остаётся своей")

        // a bad learned rule must not push purchases into «Другое»
        var badCtx = ctx
        badCtx.rules["пятер"] = TagRule(kind: "expense", group: "other", sub: "Супермаркет")
        let viaBadRule = LocalParser.parse("Пятёрочка 900", currency: "RUB", ctx: badCtx).first
        check(viaBadRule?.groupID == "food", "старое неверное правило не ломает «Пятёрочку»")

        // Claude answering with a name instead of an id
        var claudeLike = DraftExpense(amount: 1500, currency: "RUB", category: ClaudeService.resolveCategory("restaurant"),
                                      note: "Ресторан", date: Date(), source: "voice", raw: "")
        Tags.finishClaude(&claudeLike, ctx: ctx)
        check(claudeLike.groupID == "cafe", "ответ Claude «restaurant» → Кафе")

        // repair of stored records
        do {
            let container = try ModelContainer(for: Expense.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = ModelContext(container)
            let a = Expense(amount: 1200, currency: "RUB", categoryID: "other", note: "Пятерочка", date: Date(), source: "voice", subcategory: "Супермаркет")
            let b = Expense(amount: 500, currency: "RUB", categoryID: "other", note: "Мобильная связь", date: Date(), source: "voice", subcategory: "Связь")
            let c = Expense(amount: 800, currency: "RUB", categoryID: "other", note: "Корм для кота", date: Date(), source: "voice", subcategory: "Корм")
            for e in [a, b, c] { context.insert(e) }
            try context.save()
            let fixed = Repair.run(context, force: true)
            check(a.categoryID == "food" && b.categoryID == "subs" && c.categoryID == "other" && fixed == 2,
                  "починка записей: \(a.categoryID), \(b.categoryID), \(c.categoryID), исправлено \(fixed)")
        } catch {
            check(false, "хранилище: \(error)")
        }

        // these used to crash the app
        _ = LocalParser.parse("ООО Ромашка кассовый чек оплата картой итого 2350", currency: "RUB", ctx: ctx)
        let receipt = ReceiptOCR.extract(lines: ["ООО \"РОМАШКА\"", "Кассовый чек", "Молоко 89,90", "ИТОГО =2 350,00"], currency: "RUB")
        check(receipt.first.map { abs($0.amount - 2350) < 0.01 } == true, "чек: итог \(receipt.first?.amount ?? 0)")

        // draw every screen with real-looking data: periods, offsets, selections, empty state
        do {
            let container = try ModelContainer(for: Expense.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = container.mainContext
            let demo = DemoData.make(currency: "RUB")
            for d in demo {
                context.insert(Expense(amount: d.amount, currency: d.currency,
                                       categoryID: d.isIncome ? d.income.rawValue : d.category.rawValue,
                                       note: d.note, date: d.date, source: d.source,
                                       kind: d.isIncome ? "income" : "expense", subcategory: d.sub,
                                       people: d.people.joined(separator: ",")))
            }
            try context.save()
            let spends = demo.filter { !$0.isIncome }
            let incomes = demo.filter { $0.isIncome }
            let app = AppState()

            func draw<V: View>(_ view: V, _ name: String) {
                let r = ImageRenderer(content: view
                    .environmentObject(app)
                    .modelContainer(container)
                    .frame(width: 393, height: 2400))
                r.scale = 1
                check(r.uiImage != nil, "экран: \(name)")
            }

            let firstCat = Stats.slices(Stats.filter(spends, Stats.interval(.week, offset: 0)), detailed: false).first?.id
            for p in Period.allCases {
                for off in [0, -1, -2, -3] {
                    let day = Stats.interval(p, offset: off).start
                    draw(StatsView(items: spends, isDemo: false, period: p, offset: off), "аналитика \(p.rawValue) \(off)")
                    draw(StatsView(items: spends, isDemo: false, period: p, offset: off, selected: firstCat, selectedDay: day),
                         "аналитика \(p.rawValue) \(off) с выбором")
                }
            }
            draw(StatsView(items: [], isDemo: true, period: .month), "аналитика пустая")
            draw(HomeView(spends: spends, incomes: incomes, isDemo: false), "главная")
            draw(HomeView(spends: [], incomes: [], isDemo: true), "главная пустая")
            draw(BalanceView(spends: spends, incomes: incomes, isDemo: false), "баланс")
            check(RuDate.dayHeader(Date()).hasPrefix("Сегодня, "), "шапка дня: \(RuDate.dayHeader(Date()))")
            let older = RuDate.cal.date(byAdding: .day, value: -5, to: Date())!
            check(RuDate.dayHeader(older).contains(","), "шапка дня: \(RuDate.dayHeader(older))")
            draw(HistoryView(items: demo, isDemo: false), "история")
            WidgetSync.update(items: demo, currency: "RUB")
            check(true, "данные для виджета записаны")
        } catch {
            check(false, "экраны: \(error)")
        }

        print("SELFTEST \(failed == 0 ? "OK" : "FAILED") \(total - failed)/\(total)")
        fflush(stdout)
        exit(failed == 0 ? 0 : 1)
    }
}
#endif
