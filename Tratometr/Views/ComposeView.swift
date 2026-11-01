import SwiftUI
import SwiftData
import PhotosUI

/// Speak (or type, or snap a receipt) and it is saved right away. Undo is in the toast.
struct ComposeView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var speech: SpeechRecognizer
    let start: ComposeStart

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("currency") private var currency = "RUB"

    @State private var text = ""
    @State private var baseText = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var typing = false
    @State private var showScanner = false
    @State private var showGallery = false
    @State private var photoItem: PhotosPickerItem?
    @State private var savedTick = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    if typing {
                        TextField("ресторан 1500, такси 400", text: $text, axis: .vertical)
                            .lineLimit(1...6)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit { Task { await commit() } }
                    } else {
                        Text(text.isEmpty ? "Скажи, например:\n«ресторан 1500, такси 400»" : text)
                            .foregroundStyle(text.isEmpty ? Color.faint : Color.ink)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.15), value: text)
                    }
                }
                .font(.system(size: 24, weight: .semibold))
                .fontWidth(.expanded)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 34)
            }
            .scrollDismissesKeyboard(.interactively)

            Text(status)
                .font(.subheadline)
                .foregroundStyle(errorText == nil ? Color.muted : Color.bad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut, value: status)
                .padding(.bottom, 12)

            Waveform(level: speech.level, active: speech.isRunning || busy)
                .frame(height: 36)
                .padding(.bottom, 16)

            controls
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 24)
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
            if running { app.setMood(.listen) } else if !busy { app.setMood(.idle) }
        }
        .onChange(of: speech.finishedCount) { _, _ in
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if errorText == nil { errorText = "Ничего не услышал. Нажми на микрофон и скажи ещё раз." }
            } else {
                Task { await commit() }
            }
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
        if let errorText { return errorText }
        if busy { return "Записываю…" }
        if speech.isRunning { return "Слушаю. Можно несколько трат подряд" }
        if typing { return "Напиши и нажми «Готово»" }
        return "Нажми на микрофон и говори"
    }

    private var controls: some View {
        HStack {
            Menu {
                Button { openScanner() } label: { Label("Сфотографировать чек", systemImage: "doc.viewfinder") }
                Button { showGallery = true } label: { Label("Выбрать из галереи", systemImage: "photo.on.rectangle") }
            } label: {
                circle("camera", size: 52)
            }
            .accessibilityLabel("Фото чека")

            Spacer()

            Button {
                if typing { Task { await commit() } } else { toggleMic() }
            } label: {
                Image(systemName: typing ? "arrow.up" : (speech.isRunning ? "stop.fill" : "mic.fill"))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.surface)
                    .frame(width: 76, height: 76)
                    .background(Color.ink, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressScale())
            .disabled(busy || (typing && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .accessibilityLabel(typing ? "Записать" : (speech.isRunning ? "Остановить" : "Говорить"))

            Spacer()

            Button {
                withAnimation(.snappy) {
                    typing.toggle()
                    if typing {
                        speech.stop()
                        focused = true
                    } else {
                        focused = false
                        startListening()
                    }
                }
            } label: {
                circle(typing ? "mic" : "keyboard", size: 52)
            }
            .accessibilityLabel(typing ? "Говорить" : "Написать")
        }
    }

    private func circle(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(Color.surface2, in: Circle())
    }

    // MARK: actions

    private func begin() {
        switch start {
        case .voice: startListening()
        case .text: typing = true; focused = true
        case .scan: openScanner()
        case .gallery: showGallery = true
        }
    }

    private func openScanner() {
        if DocumentScanner.isAvailable { showScanner = true } else { showGallery = true }
    }

    private func startListening() {
        errorText = nil
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        baseText = t.isEmpty ? "" : t + ", "
        speech.start()
    }

    private func toggleMic() {
        if speech.isRunning { speech.stop() } else { startListening() }
    }

    private func commit() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        busy = true
        errorText = nil
        focused = false
        if speech.isRunning { speech.stop() }
        app.setMood(.think)
        let result = await ExpenseParser.parse(text: t, currency: currency, ctx: TagStore.shared.context)
        busy = false
        app.setMood(.idle)
        guard !result.items.isEmpty else {
            errorText = "Не нашёл сумму. Скажи, например: «ресторан 1500»."
            return
        }
        save(result.items)
    }

    private func scan(_ image: UIImage) async {
        busy = true
        errorText = nil
        app.setMood(.think)
        let result = await ExpenseParser.parseReceipt(image, currency: currency, ctx: TagStore.shared.context)
        busy = false
        app.setMood(.idle)
        guard !result.items.isEmpty else {
            errorText = "На фото не нашёл итоговую сумму. Сними чек ближе или скажи сумму голосом."
            return
        }
        save(result.items)
    }

    private func save(_ drafts: [DraftExpense]) {
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

        let net = items.filter { $0.currency == currency }.reduce(0) { $0 + ($1.isIncome ? $1.amount : -$1.amount) }
        let message: String
        if items.count == 1 {
            let name = top.sub.isEmpty ? top.kindName : top.sub
            let amount = (top.isIncome ? "+" : "") + Money.format(top.amount, top.currency)
            let who = top.people.isEmpty ? "" : " · с " + top.people.map { Tags.instrumental($0) }.joined(separator: ", ")
            message = "\(name) · \(amount)\(who)"
        } else {
            message = "Записал \(items.count) \(plural(items.count, "запись", "записи", "записей")) · \(Money.signed(net, currency))"
        }
        let ctx = context
        app.showToast(message, undo: {
            for e in created { ctx.delete(e) }
            try? ctx.save()
        })
        dismiss()
    }
}

/// Quiet bars that follow the voice level
struct Waveform: View {
    let level: Double
    let active: Bool
    @State private var smooth: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let n = 28
                let gap: CGFloat = 4
                let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                for i in 0..<n {
                    let phase = sin(t * 7 + Double(i) * 0.55) * 0.5 + 0.5
                    let shape = sin(Double(i) / Double(n - 1) * .pi)
                    let energy = active ? max(0.12, smooth) : 0.06
                    let h = max(3, size.height * CGFloat(energy * shape * (0.45 + 0.55 * phase)))
                    let rect = CGRect(x: CGFloat(i) * (w + gap), y: (size.height - h) / 2, width: w, height: h)
                    gc.fill(Path(roundedRect: rect, cornerRadius: w / 2), with: .color(Color.ink.opacity(0.75)))
                }
            }
        }
        .onChange(of: level) { _, v in smooth = smooth * 0.6 + v * 0.4 }
        .accessibilityHidden(true)
    }
}
