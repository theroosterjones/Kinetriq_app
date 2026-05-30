import SwiftUI

struct ContentView: View {
    @ObservedObject private var purchases = PurchaseService.shared
    @State private var selectedTab: Tab = .home

    enum Tab {
        case home, workout, history, settings
    }

    var body: some View {
        Group {
            if purchases.isLoading {
                // Brief loading screen while RevenueCat checks subscription status
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                        ProgressView().tint(.white)
                    }
                }
            } else {
                mainTabs
                    .fullScreenCover(isPresented: .init(
                        get: { !purchases.isProUser },
                        set: { _ in }
                    )) {
                        PaywallView()
                    }
            }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            ExerciseView()
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.workout)

            WorkoutHistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}
