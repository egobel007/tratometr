import Foundation
import WidgetKit

/// What the widget shows. The same struct lives in the widget target.
struct WidgetSnapshot: Codable, Equatable {
    var day: String          // yyyy-MM-dd
    var month: String        // yyyy-MM
    var today: Double
    var week: Double
    var monthSpent: Double
    var monthIncome: Double
    var symbol: String
}

/// Hands today's numbers to the widget through the shared app group.
/// Without a paid developer account the group is not shared and the widget shows only its buttons.
enum WidgetSync {
    static let group = "group.com.egorbel.tratometr"
    static let key = "widget_snapshot"

    static func update(items: [SpendItem], currency: String) {
        let main = items.filter { $0.currency == currency }
        let spends = main.filter { !$0.isIncome }
        let incomes = main.filter { $0.isIncome }
        let today = RuDate.iso(Date())
        let snap = WidgetSnapshot(
            day: today,
            month: String(today.prefix(7)),
            today: Stats.total(Stats.filter(spends, Stats.interval(.day, offset: 0))),
            week: Stats.total(Stats.filter(spends, Stats.interval(.week, offset: 0))),
            monthSpent: Stats.total(Stats.filter(spends, Stats.interval(.month, offset: 0))),
            monthIncome: Stats.total(Stats.filter(incomes, Stats.interval(.month, offset: 0))),
            symbol: CurrencyInfo.get(currency).symbol
        )
        guard let defaults = UserDefaults(suiteName: group),
              let data = try? JSONEncoder().encode(snap) else { return }
        if defaults.data(forKey: key) == data { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
