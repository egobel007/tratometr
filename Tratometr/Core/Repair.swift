import Foundation
import SwiftData

/// One-time fix for records that ended up in «Другое» although their text clearly says otherwise.
enum Repair {
    static let flag = "repair_v2_done"

    @discardableResult
    static func run(_ context: ModelContext, force: Bool = false) -> Int {
        guard force || !UserDefaults.standard.bool(forKey: flag) else { return 0 }
        let all = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        var fixed = 0
        for e in all where !e.isIncome && e.categoryID == SpendCategory.other.rawValue {
            if let g = Tags.group(forLabel: e.subcategory) {
                e.categoryID = g.group
                e.subcategory = g.sub.isEmpty ? Tags.seedSub(e.note, isIncome: false, group: g.group) : g.sub
                fixed += 1
                continue
            }
            let local = LocalParser.detectCategory(e.note + " " + e.subcategory)
            if local != .other {
                e.categoryID = local.rawValue
                e.subcategory = Tags.seedSub(e.note + " " + e.subcategory, isIncome: false, group: local.rawValue)
                fixed += 1
            }
        }
        if fixed > 0 { try? context.save() }
        UserDefaults.standard.set(true, forKey: flag)
        return fixed
    }
}
