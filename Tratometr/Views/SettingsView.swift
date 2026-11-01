import SwiftUI
import SwiftData

struct SettingsView: View {
    let items: [SpendItem]
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("currency") private var currency = "RUB"
    @AppStorage("budget") private var budget: Double = 0
    @AppStorage("salary") private var salary: Double = 0
    @ObservedObject private var tags = TagStore.shared

    @State private var budgetText = ""
    @State private var salaryText = ""
    @State private var apiKey = ""
    @State private var newPerson = ""
    @State private var confirmWipe = false
    @State private var confirmForget = false
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Валюта", selection: $currency) {
                        ForEach(CurrencyInfo.all) { c in Text("\(c.symbol)  \(c.code)").tag(c.code) }
                    }
                    amountField("Зарплата в месяц", text: $salaryText)
                    amountField("Бюджет на траты", text: $budgetText)
                } footer: {
                    Text("Зарплату можно получать частями: в «Балансе» видно, сколько уже пришло. Бюджет покажет, сколько можно тратить в день.")
                }

                Section {
                    ForEach($tags.people) { $person in
                        TextField("Имя", text: $person.name)
                    }
                    .onDelete { tags.people.remove(atOffsets: $0) }
                    HStack {
                        TextField("Добавить человека", text: $newPerson)
                        Button("Добавить") {
                            tags.addPerson(newPerson)
                            newPerson = ""
                        }
                        .disabled(newPerson.trimmingCharacters(in: .whitespaces).count < 2)
                    }
                } header: {
                    Text("Люди")
                } footer: {
                    Text("Скажи «ресторан с Ариной 3200», и в аналитике будет видно, сколько уходит на вас вместе.")
                }

                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Где взять ключ", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                } header: {
                    Text("Claude, по желанию")
                } footer: {
                    Text("Без ключа всё работает на телефоне. С ключом сложные фразы и чеки разбирает Claude, и в аналитике появляется разбор трат.")
                }

                Section("Данные") {
                    if let csvURL, !items.isEmpty {
                        ShareLink("Выгрузить в CSV", item: csvURL)
                    }
                    if tags.ruleCount > 0 {
                        Button("Забыть мои исправления категорий") { confirmForget = true }
                    }
                    Button("Удалить все записи", role: .destructive) { confirmWipe = true }
                        .disabled(items.isEmpty)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { persist(); dismiss() }
                }
            }
            .confirmationDialog("Забыть все исправления категорий?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Забыть", role: .destructive) { tags.forgetRules() }
            }
            .confirmationDialog("Удалить все траты и поступления? Это нельзя отменить.", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Удалить всё", role: .destructive) {
                    try? context.delete(model: Expense.self)
                    try? context.save()
                    app.showToast("Все записи удалены")
                }
            }
        }
        .onAppear {
            budgetText = budget > 0 ? Money.plain(budget) : ""
            salaryText = salary > 0 ? Money.plain(salary) : ""
            apiKey = Keychain.load(Keys.claude) ?? ""
            csvURL = CSVExport.write(items)
        }
        .onDisappear(perform: persist)
    }

    private func amountField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
            Text(CurrencyInfo.get(currency).symbol).foregroundStyle(Color.muted)
        }
    }

    private func persist() {
        budget = Money.parse(budgetText.replacingOccurrences(of: " ", with: ""))
        salary = Money.parse(salaryText.replacingOccurrences(of: " ", with: ""))
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key != (Keychain.load(Keys.claude) ?? "") {
            if key.isEmpty { Keychain.delete(Keys.claude) } else { Keychain.save(key, for: Keys.claude) }
        }
    }
}

enum CSVExport {
    static func write(_ items: [SpendItem]) -> URL? {
        guard !items.isEmpty else { return nil }
        var rows = [["Дата", "Время", "Тип", "Категория", "Подкатегория", "С кем", "Описание", "Сумма", "Валюта", "Источник"]]
        for e in items.sorted(by: { $0.date < $1.date }) {
            let source = e.source == "photo" ? "фото" : (e.source == "voice" ? "голос" : "текст")
            rows.append([RuDate.iso(e.date), RuDate.time(e.date), e.isIncome ? "Поступление" : "Трата",
                         e.kindName, e.sub, e.people.joined(separator: ", "), e.note, Money.plain(e.amount), e.currency, source])
        }
        let csv = "\u{FEFF}" + rows.map { r in
            r.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ";")
        }.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Траты \(RuDate.iso(Date())).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
