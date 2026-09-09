import SwiftUI

@main
struct KinetriqApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AuthService.shared.bootstrap()
        // Seed RevenueCat with the restored Supabase user ID so the first status
        // fetch already belongs to that account. A later sign-in is picked up by
        // `ContentView`'s `currentUserID` observer.
        PurchaseService.shared.configure(initialAppUserID: AuthService.shared.currentUserID)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await AuthService.shared.refreshSessionIfNeeded()
                await PurchaseService.shared.refreshStatus()
            }
        }
    }
}
