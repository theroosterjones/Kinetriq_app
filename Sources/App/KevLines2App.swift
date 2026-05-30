import SwiftUI

@main
struct KinetriqApp: App {

    init() {
        PurchaseService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
