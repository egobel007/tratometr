import SwiftUI
import SwiftData

struct SettingsView: View {
    let items: [SpendItem]
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("currency") private var currency = "RUB"
    @AppStorage("budget") private var budget: Double = 0

    @State private var budgetText = ""
    @State private var apiKey = ""
    @State private var confirmWipe = false
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Валюта", selection: $currency) {
                        ForEach(CurrencyInfo.all) { c in
                            Text("\(c.symbol)  \(c.code)").tag(c.code)
                        }
                    }
                } header: {
                    Text("Основная валюта")
                } footer: {
                    Text("Итоги и аналитика считаются в основной валюте. Траты в других валютах видны в истории.")
                }

                Section {
                    HStack {
                        TextField("Например, 60 000", text: $budgetText)
                            .keyboardType(.decimalPad)
                        Text(CurrencyInfo.get(currency).symbol).foregroundStyle(Color.muted)
                    }
                } header: {
                    Text("Бюджет на месяц")
                } footer: {
                    Text("Покажу, сколько можно тратить в день, и дам прогноз на конец месяца. Оставь пустым, если бюджет не нужен.")
                }

                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                        Label("Где взять ключ", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("Claude, по желанию")
                } footer: {
                    Text("Без ключа всё работает прямо на телефоне: речь распознаёт iPhone, суммы и категории понимает встроенный разборщик, чеки читает камера. С ключом Claude точнее понимает сложные фразы и мятые чеки и пишет личный разбор трат. Ключ хранится в связке ключей iPhone, оплата по факту использования на console.anthropic.com.")
                }

                Section("Данные") {
                    if let csvURL, !items.isEmpty {
                        ShareLink(item: csvURL) {
                            Label("Выгрузить в CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(role: .destructive) { confirmWipe = true } label: {
                        Label("Удалить все траты", systemImage: "trash")
                    }
                    .disabled(items.isEmpty)
                }

                Section("Как пользоваться") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Нажми на шар или на микрофон внизу и скажи как есть: «кофе 280, такси до работы 640, вчера Пятёрочка полторы тысячи». Через секунду тишины я сам всё разберу, останется проверить и нажать «Сохранить».")
                        Text("Чек: кнопка с камерой, затем «Сфотографировать чек». Камера сама найдёт края и прочитает итог.")
                        Text("Любую трату можно поправить или удалить, нажав на неё. В истории работает свайп влево.")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { persist(); dismiss() }
                }
            }
            .confirmationDialog("Удалить все траты? Это нельзя отменить.", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Удалить всё", role: .destructive) {
                    try? context.delete(model: Expense.self)
                    try? context.save()
                    app.showToast("Все траты удалены")
                }
            }
        }
        .onAppear {
            budgetText = budget > 0 ? Money.plain(budget) : ""
            apiKey = Keychain.load(Keys.claude) ?? ""
            csvURL = CSVExport.write(items)
        }
        .onDisappear(perform: persist)
    }

    private func persist() {
        budget = Money.parse(budgetText.replacingOccurrences(of: " ", with: ""))
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key != (Keychain.load(Keys.claude) ?? "") {
            if key.isEmpty { Keychain.delete(Keys.claude) } else { Keychain.save(key, for: Keys.claude) }
        }
    }
}

enum CSVExport {
    static func write(_ items: [SpendItem]) -> URL? {
        guard !items.isEmpty else { return nil }
        var rows = [["Дата", "Время", "Категория", "Описание", "Сумма", "Валюта", "Источник"]]
        for e in items.sorted(by: { $0.date < $1.date }) {
            let source = e.source == "photo" ? "фото" : (e.source == "voice" ? "голос" : "текст")
            rows.append([RuDate.iso(e.date), RuDate.time(e.date), e.category.name, e.note,
                         Money.plain(e.amount), e.currency, source])
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
