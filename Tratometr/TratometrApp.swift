import SwiftUI
import SwiftData

@main
struct TratometrApp: App {
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("-selftest") { SelfTest.run() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .modelContainer(for: Expense.self)
    }
}
