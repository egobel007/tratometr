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

    private let examples = ["капучино 280 и круассан 190", "вчера такси до дома 640", "Пятёрочка полторы тысячи"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(drafts.isEmpty ? "Что потратил?" : "Проверь и сохрани")
                    .font(.title3.weight(.semibold))
                    .fontWidth(.expanded)
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
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut, value: status)

                    TextField("Например: кофе 250, такси 640 и вчера продукты 2300", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.ink)
                        .padding(14)
                        .background(Color.appBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { Task { await parse() } }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Color.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if drafts.isEmpty && text.isEmpty && !speech.isRunning && busy == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(examples, id: \.self) { ex in
                                    Button { text = ex } label: {
                                        Text(ex)
                                            .font(.footnote)
                                            .foregroundStyle(Color.muted)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(Color.appBG, in: Capsule())
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

    private var status: String {
        if let busy { return busy }
        if speech.isRunning { return "Слушаю. Говори свободно: «вчера», «полторы тысячи», несколько трат подряд" }
        if !drafts.isEmpty { return "Поправь, если что-то не так, и сохрани" }
        return "Нажми на микрофон и скажи, что купил. Или напиши."
    }

    private var draftTotal: Double {
        drafts.filter { $0.currency == currency }.reduce(0) { $0 + $1.amount }
    }

    private var canSave: Bool { !drafts.isEmpty && text == parsedText && busy == nil }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button { openScanner() } label: { Label("Сфотографировать чек", systemImage: "doc.viewfinder") }
                Button { showGallery = true } label: { Label("Выбрать из галереи", systemImage: "photo.on.rectangle") }
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .frame(width: 52, height: 52)
                    .background(Color.surface2, in: Circle())
            }
            .accessibilityLabel("Фото чека")

            Button { toggleMic() } label: {
                Image(systemName: speech.isRunning ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(OrbGradient.angular))
                    .symbolEffect(.pulse, isActive: speech.isRunning)
            }
            .buttonStyle(PressScale())
            .accessibilityLabel(speech.isRunning ? "Остановить запись" : "Говорить")

            Button {
                if canSave { save() } else { Task { await parse() } }
            } label: {
                Text(canSave ? saveTitle : "Разобрать")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.surface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(primaryDisabled ? 0.4 : 1)
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
        let what = n == 1 ? "Сохранить" : "Сохранить \(n) \(plural(n, "трату", "траты", "трат"))"
        return "\(what) · \(Money.format(draftTotal, currency))"
    }

    // MARK: actions

    private func begin() {
        switch start {
        case .voice: startListening()
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
        let result = await ExpenseParser.parse(text: t, currency: currency)
        busy = nil
        parsedText = text
        app.setMood(.idle)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { drafts = result.items }
        if let notice = result.notice { app.showToast(notice) }
        if result.items.isEmpty {
            errorText = "Не нашёл сумму. Скажи, например: «обед 650» или «такси 400 рублей»."
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
            let e = Expense(amount: d.amount, currency: d.currency, categoryID: d.category.rawValue,
                            note: d.note.trimmingCharacters(in: .whitespaces), date: d.date,
                            source: d.source, rawText: String(d.raw.prefix(400)))
            context.insert(e)
            created.append(e)
        }
        try? context.save()
        savedTick += 1
        app.orb.burst(top.category.rgb)

        let total = items.filter { $0.currency == currency }.reduce(0) { $0 + $1.amount }
        let label = items.count == 1 ? top.note : "\(items.count) \(plural(items.count, "трату", "траты", "трат"))"
        let ctx = context
        app.showToast("Записал: \(label) · \(Money.format(total, currency))", undo: {
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
                CategoryIcon(category: draft.category)
                    .symbolEffect(.bounce, value: pop)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Что купил", text: $draft.note)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.ink)
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.ink)
                        .frame(width: 92)
                        .onChange(of: amountText) { _, v in draft.amount = Money.parse(v) }
                    Text(CurrencyInfo.get(draft.currency).symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.muted)
                }
                HStack(spacing: 8) {
                    categoryMenu {
                        Text(draft.category.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(draft.category.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(draft.category.color.opacity(0.13), in: Capsule())
                    }
                    DatePicker("Дата", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .scaleEffect(0.86, anchor: .leading)
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

    private func categoryMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            ForEach(SpendCategory.allCases) { c in
                Button {
                    let wasDefaultNote = draft.note.isEmpty || SpendCategory.allCases.contains { $0.name == draft.note }
                    draft.category = c
                    if wasDefaultNote { draft.note = c.name }
                    pop += 1
                } label: {
                    Label(c.name, systemImage: c.symbol)
                }
            }
        } label: {
            label()
        }
    }
}
