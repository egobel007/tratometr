import SwiftUI
import SwiftData

/// "Куда отнести?" One tap fixes the category and teaches the app.
struct QuickCategoryView: View {
    let expense: Expense
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Куда отнести?")
                        .font(.system(size: 22, weight: .semibold))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.ink)
                    Text("\(expense.note) · \(expense.isIncome ? "+" : "−")\(Money.format(expense.amount, expense.currency))")
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    if expense.isIncome {
                        ForEach(IncomeSource.allCases) { s in
                            tile(s.symbol, s.color, s.name, current: expense.categoryID == s.rawValue) { pick(group: s.rawValue, name: s.name) }
                        }
                    } else {
                        ForEach(SpendCategory.allCases) { c in
                            tile(c.symbol, c.color, c.name, current: expense.categoryID == c.rawValue) { pick(group: c.rawValue, name: c.name) }
                        }
                    }
                }

                Text("Я запомню выбор и дальше буду относить такие записи сюда сам.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
            .padding(24)
        }
        .background(Color.surface)
    }

    private func tile(_ symbol: String, _ color: Color, _ name: String, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ItemIcon(symbol: symbol, color: color, size: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(current ? Color.ink : Color.clear, lineWidth: 1.5)
                    )
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(height: 28, alignment: .top)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScale())
    }

    private func pick(group: String, name: String) {
        let sub = Tags.seedSub(expense.note, isIncome: expense.isIncome, group: group)
        expense.categoryID = group
        expense.subcategory = sub
        try? context.save()
        TagStore.shared.learn(note: expense.note, isIncome: expense.isIncome, group: group, sub: sub)
        app.showToast("Запомнил: «\(expense.note)» → \(name)")
        dismiss()
    }
}
