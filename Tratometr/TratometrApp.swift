import SwiftUI
import SwiftData

@main
struct TratometrApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .modelContainer(for: Expense.self)
    }
}
