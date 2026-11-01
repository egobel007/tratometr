import SwiftUI
import SwiftData
import PhotosUI

/// Voice / text / receipt input, then a review of what was understood.
struct ComposeView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var speech: SpeechRecognizer
    let start: ComposeStart

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("currency") private var currency = "RUB"

    @State private var text = ""
    @State private var baseText = ""
    @State private var parsedText = ""
    @State private var drafts: [DraftExpense] = []
    @State private var busy: String?
    @State private var errorText: String?
    @State private var showScanner = false
    @State private var showGallery = false
    @State private var photoItem: PhotosPickerItem?
    @State private var savedTick = 0
    @FocusState private var focused: Bool

    private var incomeMode: Bool { start == .income }

    private var examples: [String] {
        incomeMode
            ? ["пришло 40 000, часть зарплаты", "продал велосипед за 15 тысяч", "кэшбэк 1200"]
            : ["капучино 280 и круассан 190", "вчера такси до дома 640", "пришло 40 000, часть зарплаты"]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.opacity)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.muted)
                        .frame(width: 32, height: 32)
                        .background(Color.surface2, in: Circle())
                }
                .accessibilityLabel("Закрыть")
            }
            .padding(.top, 22)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 14) {
                    OrbView(engine: app.orb)
                        .frame(width: 112, height: 112)
                        .onTapGesture { toggleMic() }

                    Text(status)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut, value: status)

                    TextField(incomeMode ? "Например: пришло 40 000, часть зарплаты"
                                         : "Например: кофе 250, такси 640 или «пришло 40 000»",
                              text: $text, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .padding(14)
                        .background(Color.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(focused ? Color.violet.opacity(0.5) : Color.clear, lineWidth: 1.5))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { Task { await parse() } }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if drafts.isEmpty && text.isEmpty && !speech.isRunning && busy == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(examples, id: \.self) { ex in
                                    Button { text = ex } label: {
                                        Text(ex)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(Color.violet)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(Color.violet.opacity(0.10), in: Capsule())
                                    }
                                }
                            }
                        }
                    }

                    ForEach($drafts) { $draft in
                        DraftRow(draft: $draft) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                drafts.removeAll { $0.id == draft.id }
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .modifier(active: Tilt3D(angle: -45, offset: 20),
                                                                         identity: Tilt3D(angle: 0, offset: 0))),
                            removal: .opacity.combined(with: .scale(scale: 0.9))))
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)

            actionBar
        }
        .padding(.horizontal, 20)
        .background(Color.surface)
        .sensoryFeedback(.success, trigger: savedTick)
        .onAppear(perform: begin)
        .onDisappear {
            speech.stop()
            app.setMood(.idle)
        }
        .onChange(of: speech.transcript) { _, new in
            if speech.isRunning { text = baseText + new }
        }
        .onChange(of: speech.level) { _, level in app.orb.voice(level) }
        .onChange(of: speech.isRunning) { _, running in
            if running { app.setMood(.listen) } else if busy == nil { app.setMood(.idle) }
        }
        .onChange(of: speech.finishedCount) { _, _ in
            if drafts.isEmpty || text != parsedText { Task { await parse() } }
        }
        .onChange(of: speech.errorText) { _, e in if let e { errorText = e } }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { image in
                showScanner = false
                if let image { Task { await scan(image) } }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showGallery, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await scan(image)
                }
                photoItem = nil
            }
        }
    }

    // MARK: pieces

    private var title: String {
        if !drafts.isEmpty { return "Проверь и сохрани" }
        return incomeMode ? "Сколько пришло?" : "Что потратил?"
    }

    private var status: String {
        if let busy { return busy }
        if speech.isRunning { return "Слушаю! Говори свободно: траты, «пришло 40 000», «вчера», «полторы тысячи»" }
        if !drafts.isEmpty { return "Поправь, если что-то не так, и сохрани" }
        return incomeMode ? "Нажми на микрофон и скажи, сколько и откуда пришло" : "Нажми на микрофон и скажи, что купил или сколько пришло"
    }

    private var draftNet: Double {
        drafts.filter { $0.currency == currency }.reduce(0) { $0 + ($1.isIncome ? $1.amount : -$1.amount) }
    }

    private var canSave: Bool { !drafts.isEmpty && text == parsedText && busy == nil }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button { openScanner() } label: { Label("Сфотографировать чек", systemImage: "doc.viewfinder") }
                Button { showGallery = true } label: { Label("Выбрать из галереи", systemImage: "photo.on.rectangle") }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.sky)
                    .frame(width: 52, height: 52)
                    .background(Color.sky.opacity(0.14), in: Circle())
            }
            .accessibilityLabel("Фото чека")

            Button { toggleMic() } label: {
                Image(systemName: speech.isRunning ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Palette.orb))
                    .shadow(color: Color.bubble.opacity(0.4), radius: 10, y: 5)
                    .symbolEffect(.pulse, isActive: speech.isRunning)
            }
            .buttonStyle(PressScale())
            .accessibilityLabel(speech.isRunning ? "Остановить запись" : "Говорить")

            Button {
                if canSave { save() } else { Task { await parse() } }
            } label: {
                Text(canSave ? saveTitle : "Разобрать")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSave ? AnyShapeStyle(Palette.plus) : AnyShapeStyle(Palette.accent),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(primaryDisabled ? 0.45 : 1)
            }
            .buttonStyle(PressScale())
            .disabled(primaryDisabled)
        }
        .padding(.vertical, 12)
    }

    private var primaryDisabled: Bool {
        busy != nil || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && drafts.isEmpty)
    }

    private var saveTitle: String {
        let n = drafts.count
        let what = n == 1 ? "Сохранить" : "Сохранить \(n)"
        return "\(what) · \(Money.signed(draftNet, currency))"
    }

    // MARK: actions

    private func begin() {
        switch start {
        case .voice, .income: startListening()
        case .text: focused = true
        case .scan: openScanner()
        case .gallery: showGallery = true
        }
    }

    private func openScanner() {
        if DocumentScanner.isAvailable { showScanner = true } else { showGallery = true }
    }

    private func startListening() {
        errorText = nil
        focused = false
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        baseText = t.isEmpty ? "" : t + ", "
        speech.start()
    }

    private func toggleMic() {
        if speech.isRunning { speech.stop() } else { startListening() }
    }

    private func parse() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, busy == nil else { return }
        busy = "Разбираю…"
        errorText = nil
        focused = false
        if speech.isRunning { speech.stop() }
        app.setMood(.think)
        let result = await ExpenseParser.parse(text: t, currency: currency, forceIncome: incomeMode, ctx: TagStore.shared.context)
        busy = nil
        parsedText = text
        app.setMood(.idle)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { drafts = result.items }
        if let notice = result.notice { app.showToast(notice) }
        if result.items.isEmpty {
            errorText = "Не нашёл сумму. Скажи, например: «обед 650» или «пришло 40 000»."
        }
    }

    private func scan(_ image: UIImage) async {
        busy = "Читаю чек…"
        errorText = nil
        app.setMood(.think)
        let result = await ExpenseParser.parseReceipt(image, currency: currency, ctx: TagStore.shared.context)
        busy = nil
        app.setMood(.idle)
        if result.items.isEmpty {
            errorText = "На фото не нашёл итоговую сумму. Сними чек ближе или скажи сумму голосом."
            return
        }
        text = result.items.map { "\($0.note) \(Money.plain($0.amount))" }.joined(separator: ", ")
        parsedText = text
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { drafts = result.items }
        if let notice = result.notice { app.showToast(notice) }
    }

    private func save() {
        let items = drafts.filter { $0.amount > 0 }
        guard let top = items.max(by: { $0.amount < $1.amount }) else { return }
        var created: [Expense] = []
        for d in items {
            let e = Expense(amount: d.amount, currency: d.currency, categoryID: d.categoryID,
                            note: d.note.trimmingCharacters(in: .whitespaces), date: d.date,
                            source: d.source, rawText: String(d.raw.prefix(400)),
                            kind: d.isIncome ? "income" : "expense",
                            subcategory: d.sub.trimmingCharacters(in: .whitespaces),
                            people: d.people.joined(separator: ","))
            context.insert(e)
            created.append(e)
            TagStore.shared.remember(d)
        }
        try? context.save()
        savedTick += 1
        app.orb.burst(top.isIncome ? top.income.rgb : top.category.rgb)
        app.confetti += 1

        let incomeCount = items.filter(\.isIncome).count
        let label: String
        if items.count == 1 {
            label = top.isIncome ? "Пришло: \(top.note)" : "Записал: \(top.note)"
        } else if incomeCount == items.count {
            label = "Записал \(items.count) \(plural(items.count, "поступление", "поступления", "поступлений"))"
        } else {
            label = "Записал \(items.count) \(plural(items.count, "запись", "записи", "записей"))"
        }
        let ctx = context
        app.showToast("\(label) · \(Money.signed(draftNet, currency))", undo: {
            for e in created { ctx.delete(e) }
            try? ctx.save()
        })
        dismiss()
    }
}

struct DraftRow: View {
    @Binding var draft: DraftExpense
    var onDelete: () -> Void
    @ObservedObject private var tags = TagStore.shared
    @State private var amountText = ""
    @State private var pop = 0
    @State private var askSub = false
    @State private var newSub = ""
    @State private var askPerson = false
    @State private var newPerson = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            categoryMenu {
                ItemIcon(symbol: draft.symbol, color: draft.color)
                    .symbolEffect(.bounce, value: pop)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField(draft.isIncome ? "Что пришло" : "Что купил", text: $draft.note)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text(draft.isIncome ? "+" : "−")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(draft.isIncome ? Color.good : Color.muted)
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(draft.isIncome ? Color.good : Color.ink)
                        .frame(width: 84)
                        .onChange(of: amountText) { _, v in draft.amount = Money.parse(v) }
                    Text(CurrencyInfo.get(draft.currency).symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.muted)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                let wasDefault = isDefaultNote
                                draft.isIncome.toggle()
                                draft.sub = ""
                                draft.edited = true
                                if wasDefault { draft.note = draft.kindName }
                                pop += 1
                            }
                        } label: {
                            Chip(title: draft.isIncome ? "Доход" : "Трата", color: draft.isIncome ? .good : .warm)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Переключить трату и доход")

                        categoryMenu { Chip(title: draft.kindName, color: draft.color) }

                        subMenu

                        DatePicker("Дата", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .fixedSize()
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(peopleChoices, id: \.self) { name in
                            let on = draft.people.contains(name)
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if on { draft.people.removeAll { $0 == name } } else { draft.people.append(name) }
                                }
                            } label: {
                                Chip(title: on ? "с " + Tags.instrumental(name) : name,
                                     symbol: on ? "heart.fill" : "heart", color: .bubble, filled: on)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { newPerson = ""; askPerson = true } label: {
                            Chip(title: "Кто-то ещё", symbol: "person.badge.plus", color: .bubble, filled: false)
                        }
                        .buttonStyle(.plain)

                        Button(action: onDelete) {
                            Chip(title: "Убрать", symbol: "xmark", color: .muted, filled: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { amountText = Money.plain(draft.amount) }
        .alert("Новая подкатегория", isPresented: $askSub) {
            TextField("Например, Столовая", text: $newSub)
            Button("Добавить") {
                let s = Tags.capitalized(newSub.trimmingCharacters(in: .whitespaces))
                guard !s.isEmpty else { return }
                draft.sub = s
                draft.edited = true
                tags.registerSub(isIncome: draft.isIncome, group: draft.groupID, sub: s)
                pop += 1
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Внутри «\(draft.kindName)». Я запомню её и дальше буду раскладывать такие траты сам.")
        }
        .alert("С кем была трата?", isPresented: $askPerson) {
            TextField("Имя", text: $newPerson)
            Button("Добавить") {
                if let name = tags.addPerson(newPerson), !draft.people.contains(name) {
                    draft.people.append(name)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var peopleChoices: [String] {
        Tags.uniq(tags.people.map(\.name) + draft.people)
    }

    private var isDefaultNote: Bool {
        draft.note.isEmpty
            || SpendCategory.allCases.contains { $0.name == draft.note }
            || IncomeSource.allCases.contains { $0.name == draft.note }
    }

    private var subMenu: some View {
        let options = Tags.uniq(tags.subs(isIncome: draft.isIncome, group: draft.groupID) + (draft.sub.isEmpty ? [] : [draft.sub]))
        return Menu {
            Button {
                draft.sub = ""
                draft.edited = true
            } label: {
                if draft.sub.isEmpty { Label("Без уточнения", systemImage: "checkmark") } else { Text("Без уточнения") }
            }
            ForEach(options, id: \.self) { name in
                Button {
                    draft.sub = name
                    draft.edited = true
                    pop += 1
                } label: {
                    if draft.sub == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            Button { newSub = ""; askSub = true } label: { Label("Новая подкатегория…", systemImage: "plus") }
        } label: {
            Chip(title: draft.sub.isEmpty ? "Уточнить" : draft.sub,
                 symbol: draft.sub.isEmpty ? "plus" : "tag.fill",
                 color: draft.color, filled: !draft.sub.isEmpty)
        }
    }

    private func categoryMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            if draft.isIncome {
                ForEach(IncomeSource.allCases) { s in
                    Button {
                        let wasDefault = isDefaultNote
                        draft.income = s
                        draft.sub = ""
                        draft.edited = true
                        if wasDefault { draft.note = s.name }
                        pop += 1
                    } label: { Label(s.name, systemImage: s.symbol) }
                }
            } else {
                ForEach(SpendCategory.allCases) { c in
                    Button {
                        let wasDefault = isDefaultNote
                        draft.category = c
                        draft.sub = ""
                        draft.edited = true
                        if wasDefault { draft.note = c.name }
                        pop += 1
                    } label: { Label(c.name, systemImage: c.symbol) }
                }
            }
        } label: {
            label()
        }
    }
}
