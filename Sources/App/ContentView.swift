import SwiftUI

struct ContentView: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var purchases = PurchaseService.shared
    @StateObject private var router = AppRouter()

    var body: some View {
        Group {
            if !auth.isAuthenticated {
                LoginView()
            } else if purchases.isLoading {
                loadingView
            } else {
                mainTabs
                    .fullScreenCover(isPresented: .init(
                        get: { !purchases.hasProAccess },
                        set: { _ in }
                    )) {
                        PaywallView()
                    }
            }
        }
        .tint(KColor.accent)
        .onChange(of: auth.currentUserID) { _, newUserID in
            guard let newUserID else { return }
            Task { await purchases.identify(appUserID: newUserID) }
        }
    }

    private var loadingView: some View {
        ZStack {
            KColor.background.ignoresSafeArea()
            VStack(spacing: KSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(KColor.accent.opacity(0.14))
                        .frame(width: 110, height: 110)
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(KColor.brandGradient)
                }
                Text("Kinetriq")
                    .font(KFont.title)
                    .foregroundStyle(KColor.textPrimary)
                ProgressView()
                    .tint(KColor.accent)
            }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "square.grid.2x2.fill") }
                .tag(AppRouter.Tab.home)

            ExerciseView()
                .tabItem { Label("Analyze", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppRouter.Tab.workout)

            WorkoutHistoryView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppRouter.Tab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppRouter.Tab.settings)
        }
        .environmentObject(router)
    }
}
