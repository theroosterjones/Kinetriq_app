import SwiftUI

@main
struct KinetriqApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AuthService.shared.bootstrap()
        PurchaseService.shared.configure()
        if let userID = AuthService.shared.currentUserID {
            Task { await PurchaseService.shared.identify(appUserID: userID) }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await PurchaseService.shared.refreshStatus() }
        }
    }
}
