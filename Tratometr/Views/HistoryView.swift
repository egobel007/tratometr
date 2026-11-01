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
    @State private var editing: Expense?

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [SpendItem]
        var id: Date { day }
    }

    var body: some View {
        let q = Tags.norm(query.trimmingCharacters(in: .whitespaces))
        let filtered = q.isEmpty ? items : items.filter {
            Tags.norm($0.note).contains(q) || Tags.norm($0.kindName).contains(q) || Tags.norm($0.sub).contains(q)
                || $0.people.contains { Tags.norm($0).hasPrefix(Tags.nameStem(q)) } || Money.plain($0.amount).contains(q)
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
                    Text(q.isEmpty ? "Здесь пока пусто." : "Ничего не нашёл.")
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
                        dayHeader(g)
                    }
                }
                Color.clear.frame(height: 90).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBG)
            .navigationTitle("История")
            .searchable(text: $query, prompt: "Кофе, Арина, 1500")
        }
        .sheet(item: $editing) { EditExpenseView(expense: $0) }
    }

    private func dayHeader(_ g: DayGroup) -> some View {
        let main = g.items.filter { $0.currency == currency }
        let spent = Stats.total(main.filter { !$0.isIncome })
        let came = Stats.total(main.filter { $0.isIncome })
        return HStack(spacing: 8) {
            Text(RuDate.dayLabel(g.day)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
            Spacer()
            if came > 0 { Text("+" + Money.format(came, currency)).foregroundStyle(Color.good) }
            if spent > 0 { Text("−" + Money.format(spent, currency)).foregroundStyle(Color.muted) }
        }
        .font(.subheadline)
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
        let extra = (e.subcategory, e.people)
        context.delete(e)
        try? context.save()
        let ctx = context
        app.showToast("Удалил", undo: {
            ctx.insert(Expense(amount: copy.0, currency: copy.1, categoryID: copy.2, note: copy.3,
                               date: copy.4, source: copy.5, rawText: copy.6, kind: copy.7,
                               subcategory: extra.0, people: extra.1))
            try? ctx.save()
        })
    }
}

/// Simple form to fix a record. Changes teach the parser.
struct EditExpenseView: View {
    let expense: Expense
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var tags = TagStore.shared

    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var isIncome = false
    @State private var category: SpendCategory = .other
    @State private var income: IncomeSource = .other
    @State private var sub = ""
    @State private var people: [String] = []
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
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 30, weight: .semibold))
                            .fontWidth(.expanded)
                        Text(CurrencyInfo.get(expense.currency).symbol)
                            .font(.title2)
                            .foregroundStyle(Color.muted)
                    }
                    TextField(isIncome ? "Что пришло" : "Что купил", text: $note)
                    DatePicker("Когда", selection: $date, in: ...Date())
                }
                Section {
                    if isIncome {
                        Picker("Откуда", selection: $income) {
                            ForEach(IncomeSource.allCases) { s in Label(s.name, systemImage: s.symbol).tag(s) }
                        }
                    } else {
                        Picker("Категория", selection: $category) {
                            ForEach(SpendCategory.allCases) { c in Label(c.name, systemImage: c.symbol).tag(c) }
                        }
                    }
                    Picker("Уточнение", selection: $sub) {
                        Text("Без уточнения").tag("")
                        ForEach(subOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Своё уточнение", text: $sub)
                } footer: {
                    Text("Я запомню исправление и дальше буду раскладывать такие записи сам.")
                }
                if !tags.people.isEmpty || !people.isEmpty {
                    Section("С кем") {
                        ForEach(Tags.uniq(tags.people.map(\.name) + people), id: \.self) { name in
                            Toggle(name, isOn: Binding(
                                get: { people.contains(name) },
                                set: { on in
                                    if on { if !people.contains(name) { people.append(name) } } else { people.removeAll { $0 == name } }
                                }
                            ))
                        }
                    }
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
            sub = expense.subcategory
            people = expense.peopleList
        }
    }

    private var subOptions: [String] {
        let list = tags.subs(isIncome: isIncome, group: isIncome ? income.rawValue : category.rawValue)
        let current = sub.trimmingCharacters(in: .whitespaces)
        return Tags.uniq(list + (current.isEmpty ? [] : [current]))
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        let cleanSub = Tags.capitalized(sub.trimmingCharacters(in: .whitespaces))
        let group = isIncome ? income.rawValue : category.rawValue
        let changed = expense.isIncome != isIncome || expense.categoryID != group || expense.subcategory != cleanSub

        expense.amount = Money.parse(amountText)
        expense.kind = isIncome ? "income" : "expense"
        expense.categoryID = group
        expense.subcategory = cleanSub
        expense.people = people.joined(separator: ",")
        expense.note = trimmed.isEmpty ? (isIncome ? income.name : category.name) : trimmed
        expense.date = date
        try? context.save()

        tags.registerSub(isIncome: isIncome, group: group, sub: cleanSub)
        if changed { tags.learn(note: expense.note, isIncome: isIncome, group: group, sub: cleanSub) }
        dismiss()
    }
}
