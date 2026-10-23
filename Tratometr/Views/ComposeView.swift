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
        let result = await ExpenseParser.parse(text: t, currency: currency, forceIncome: incomeMode)
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
        let result = await ExpenseParser.parseReceipt(image, currency: currency)
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
                            kind: d.isIncome ? "income" : "expense")
            context.insert(e)
            created.append(e)
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
    @State private var amountText = ""
    @State private var pop = 0

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
                        .frame(width: 88)
                        .onChange(of: amountText) { _, v in draft.amount = Money.parse(v) }
                    Text(CurrencyInfo.get(draft.currency).symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.muted)
                }
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            let wasDefault = isDefaultNote
                            draft.isIncome.toggle()
                            if wasDefault { draft.note = draft.kindName }
                            pop += 1
                        }
                    } label: {
                        Text(draft.isIncome ? "Доход" : "Трата")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(draft.isIncome ? Color.good : Color.warm)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background((draft.isIncome ? Color.good : Color.warm).opacity(0.13), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Переключить трату и доход")

                    categoryMenu {
                        Text(draft.kindName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(draft.color)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(draft.color.opacity(0.13), in: Capsule())
                    }
                    DatePicker("Дата", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .scaleEffect(0.82, anchor: .leading)
                        .frame(maxWidth: 110, alignment: .leading)
                    Spacer(minLength: 0)
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.muted)
                            .frame(width: 26, height: 26)
                            .background(Color.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Убрать")
                }
            }
        }
        .padding(12)
        .background(Color.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { amountText = Money.plain(draft.amount) }
    }

    private var isDefaultNote: Bool {
        draft.note.isEmpty
            || SpendCategory.allCases.contains { $0.name == draft.note }
            || IncomeSource.allCases.contains { $0.name == draft.note }
    }

    private func categoryMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            if draft.isIncome {
                ForEach(IncomeSource.allCases) { s in
                    Button {
                        let wasDefault = isDefaultNote
                        draft.income = s
                        if wasDefault { draft.note = s.name }
                        pop += 1
                    } label: { Label(s.name, systemImage: s.symbol) }
                }
            } else {
                ForEach(SpendCategory.allCases) { c in
                    Button {
                        let wasDefault = isDefaultNote
                        draft.category = c
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
