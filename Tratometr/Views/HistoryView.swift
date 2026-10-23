import SwiftUI
import SwiftData

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    let items: [SpendItem]
    let isDemo: Bool

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var records: [Expense]
    @AppStorage("currency") private var currency = "RUB"
    @State private var query = ""
    @State private var filter = 0   // 0 all, 1 spending, 2 income
    @State private var editing: Expense?

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [SpendItem]
        var id: Date { day }
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let byKind = items.filter { filter == 0 || (filter == 1 && !$0.isIncome) || (filter == 2 && $0.isIncome) }
        let filtered = q.isEmpty ? byKind : byKind.filter {
            $0.note.lowercased().contains(q) || $0.kindName.lowercased().contains(q) || Money.plain($0.amount).contains(q)
        }
        let groups = Dictionary(grouping: filtered.prefix(600)) { RuDate.cal.startOfDay(for: $0.date) }
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }

        NavigationStack {
            List {
                Picker("Показать", selection: $filter) {
                    Text("Всё").tag(0)
                    Text("Траты").tag(1)
                    Text("Доходы").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if isDemo {
                    DemoBanner()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if groups.isEmpty {
                    Text(q.isEmpty ? "Здесь пока пусто." : "Ничего не нашёл.")
                        .foregroundStyle(Color.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(groups) { g in
                    Section {
                        ForEach(g.items) { item in
                            Button { open(item) } label: { ExpenseRow(item: item, showDate: false) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.surface.opacity(0.7))
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
                        dayHeader(g)
                    }
                }
                Color.clear.frame(height: 100).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("История")
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(text: $query, prompt: "Кофе, зарплата, 1500")
        }
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    private func dayHeader(_ g: DayGroup) -> some View {
        let main = g.items.filter { $0.currency == currency }
        let spent = Stats.total(main.filter { !$0.isIncome })
        let came = Stats.total(main.filter { $0.isIncome })
        return HStack(spacing: 8) {
            Text(RuDate.dayLabel(g.day))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
            Spacer()
            if came > 0 {
                Text("+" + Money.format(came, currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.good)
            }
            if spent > 0 {
                Text("−" + Money.format(spent, currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.muted)
            }
        }
        .monospacedDigit()
        .textCase(nil)
    }

    private func open(_ item: SpendItem) {
        if isDemo {
            app.showToast("Это пример. Запиши свою трату, и пример исчезнет.")
            return
        }
        editing = records.first { $0.uid.uuidString == item.id }
    }

    private func delete(_ item: SpendItem) {
        guard let e = records.first(where: { $0.uid.uuidString == item.id }) else { return }
        let copy = (e.amount, e.currency, e.categoryID, e.note, e.date, e.source, e.rawText, e.kind)
        context.delete(e)
        try? context.save()
        let ctx = context
        app.showToast("Удалил", undo: {
            ctx.insert(Expense(amount: copy.0, currency: copy.1, categoryID: copy.2, note: copy.3,
                               date: copy.4, source: copy.5, rawText: copy.6, kind: copy.7))
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
    @State private var isIncome = false
    @State private var category: SpendCategory = .other
    @State private var income: IncomeSource = .other
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $isIncome) {
                        Text("Трата").tag(false)
                        Text("Поступление").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Сумма") {
                    HStack {
                        Text(isIncome ? "+" : "−")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(isIncome ? Color.good : Color.muted)
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(CurrencyInfo.get(expense.currency).symbol)
                            .font(.title2)
                            .foregroundStyle(Color.muted)
                    }
                }
                Section(isIncome ? "Что пришло" : "Что купил") {
                    TextField("Описание", text: $note)
                }
                Section("Когда") {
                    DatePicker("Дата и время", selection: $date, in: ...Date())
                }
                Section(isIncome ? "Откуда" : "Категория") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        if isIncome {
                            ForEach(IncomeSource.allCases) { s in
                                tile(symbol: s.symbol, color: s.color, name: s.name, selected: income == s) { income = s }
                            }
                        } else {
                            ForEach(SpendCategory.allCases) { c in
                                tile(symbol: c.symbol, color: c.color, name: c.name, selected: category == c) { category = c }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button(isIncome ? "Удалить поступление" : "Удалить трату", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(isIncome ? "Поступление" : "Трата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(Money.parse(amountText) <= 0)
                }
            }
            .confirmationDialog("Удалить эту запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
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
            isIncome = expense.isIncome
            category = expense.category
            income = expense.incomeSource
        }
    }

    private func tile(symbol: String, color: Color, name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) { action() }
        } label: {
            VStack(spacing: 6) {
                ItemIcon(symbol: symbol, color: color, size: 38)
                Text(name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? color.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        expense.amount = Money.parse(amountText)
        expense.kind = isIncome ? "income" : "expense"
        expense.categoryID = isIncome ? income.rawValue : category.rawValue
        expense.note = trimmed.isEmpty ? (isIncome ? income.name : category.name) : trimmed
        expense.date = date
        try? context.save()
        dismiss()
    }
}
