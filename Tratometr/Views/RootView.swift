import SwiftUI
import SwiftData

struct RootView: View {
    @StateObject private var app = AppState()
    @Query(sort: \Expense.date, order: .reverse) private var records: [Expense]
    @AppStorage("currency") private var currency = "RUB"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let real = records.map { SpendItem($0) }
        let isDemo = real.isEmpty
        let all = isDemo ? DemoData.make(currency: currency) : real
        let spends = all.filter { !$0.isIncome }
        let incomes = all.filter { $0.isIncome }

        ZStack(alignment: .bottom) {
            AppBackground()

            Group {
                switch app.tab {
                case .home: HomeView(spends: spends, incomes: incomes, isDemo: isDemo)
                case .balance: BalanceView(spends: spends, incomes: incomes, isDemo: isDemo)
                case .stats: StatsView(items: spends, isDemo: isDemo)
                case .history: HistoryView(items: all, isDemo: isDemo)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .modifier(active: Tilt3D(angle: 9, offset: 14),
                                                             identity: Tilt3D(angle: 0, offset: 0))),
                removal: .opacity))

            TabBar()

            if let toast = app.toast {
                ToastView(message: toast)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

            ConfettiBurst(trigger: app.confetti)
                .zIndex(3)
        }
        .environmentObject(app)
        .sheet(item: $app.compose) { start in
            ComposeView(speech: app.speech, start: start)
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(30)
                .presentationBackground(Color.surface)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView(items: real)
                .environmentObject(app)
        }
        .onAppear { app.motion.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.motion.start() } else { app.motion.stop() }
        }
    }
}
