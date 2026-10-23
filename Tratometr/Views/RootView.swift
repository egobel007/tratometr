import SwiftUI
import SwiftData

struct RootView: View {
    @StateObject private var app = AppState()
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @AppStorage("currency") private var currency = "RUB"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let real = expenses.map { SpendItem($0) }
        let isDemo = real.isEmpty
        let items = isDemo ? DemoData.make(currency: currency) : real

        ZStack(alignment: .bottom) {
            Color.appBG.ignoresSafeArea()

            Group {
                switch app.tab {
                case .home: HomeView(items: items, isDemo: isDemo)
                case .stats: StatsView(items: items, isDemo: isDemo)
                case .history: HistoryView(items: items, isDemo: isDemo)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .modifier(active: Tilt3D(angle: 9, offset: 14),
                                                             identity: Tilt3D(angle: 0, offset: 0))),
                removal: .opacity))

            TabBar()

            if let toast = app.toast {
                ToastView(message: toast)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .environmentObject(app)
        .sheet(item: $app.compose) { start in
            ComposeView(speech: app.speech, start: start)
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
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
