import SwiftUI
import SwiftData

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    let items: [SpendItem]
    let isDemo: Bool

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @AppStorage("currency") private var currency = "RUB"
    @State private var query = ""
    @State private var editing: Expense?

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [SpendItem]
        var id: Date { day }
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? items : items.filter {
            $0.note.lowercased().contains(q) || $0.category.name.lowercased().contains(q) || Money.plain($0.amount).contains(q)
        }
        let groups = Dictionary(grouping: filtered.prefix(600)) { RuDate.cal.startOfDay(for: $0.date) }
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }

        NavigationStack {
            List {
                if isDemo {
                    DemoBanner()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if groups.isEmpty {
                    Text(q.isEmpty ? "Трат пока нет." : "Ничего не нашёл.")
                        .foregroundStyle(Color.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(groups) { g in
                    Section {
                        ForEach(g.items) { item in
                            Button { open(item) } label: { ExpenseRow(item: item, showDate: false) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.appBG)
                                .listRowSeparatorTint(Color.line)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !isDemo {
                                        Button(role: .destructive) { delete(item) } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(RuDate.dayLabel(g.day)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                            Spacer()
                            Text(Money.format(Stats.total(g.items.filter { $0.currency == currency }), currency))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Color.muted)
                        }
                        .textCase(nil)
                    }
                }
                Color.clear.frame(height: 90).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBG)
            .navigationTitle("Все траты")
            .searchable(text: $query, prompt: "Кофе, такси, 1500")
        }
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    private func open(_ item: SpendItem) {
        if isDemo {
            app.showToast("Это пример. Запиши свою трату, и пример исчезнет.")
            return
        }
        editing = expenses.first { $0.uid.uuidString == item.id }
    }

    private func delete(_ item: SpendItem) {
        guard let e = expenses.first(where: { $0.uid.uuidString == item.id }) else { return }
        let copy = (e.amount, e.currency, e.categoryID, e.note, e.date, e.source, e.rawText)
        context.delete(e)
        try? context.save()
        let ctx = context
        app.showToast("Удалил", undo: {
            ctx.insert(Expense(amount: copy.0, currency: copy.1, categoryID: copy.2, note: copy.3,
                               date: copy.4, source: copy.5, rawText: copy.6))
            try? ctx.save()
        })
    }
}

struct EditExpenseView: View {
    let expense: Expense
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var category: SpendCategory = .other
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Сумма") {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 28, weight: .semibold))
                            .fontWidth(.expanded)
                        Text(CurrencyInfo.get(expense.currency).symbol)
                            .font(.title2)
                            .foregroundStyle(Color.muted)
                    }
                }
                Section("Что купил") {
                    TextField("Описание", text: $note)
                }
                Section("Когда") {
                    DatePicker("Дата и время", selection: $date, in: ...Date())
                }
                Section("Категория") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(SpendCategory.allCases) { c in
                            Button { withAnimation(.spring(response: 0.3)) { category = c } } label: {
                                VStack(spacing: 6) {
                                    CategoryIcon(category: c, size: 38)
                                    Text(c.name)
                                        .font(.caption2)
                                        .foregroundStyle(Color.ink)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(category == c ? Color.ink : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Удалить трату", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Трата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(Money.parse(amountText) <= 0)
                }
            }
            .confirmationDialog("Удалить эту трату?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    context.delete(expense)
                    try? context.save()
                    dismiss()
                }
            }
        }
        .onAppear {
            amountText = Money.plain(expense.amount)
            note = expense.note
            date = expense.date
            category = expense.category
        }
    }

    private func save() {
        expense.amount = Money.parse(amountText)
        expense.note = note.trimmingCharacters(in: .whitespaces).isEmpty ? category.name : note.trimmingCharacters(in: .whitespaces)
        expense.date = date
        expense.categoryID = category.rawValue
        try? context.save()
        dismiss()
    }
}
