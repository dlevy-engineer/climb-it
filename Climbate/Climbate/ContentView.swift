//
//  ContentView.swift
//  CLIMB.it
//
//  Main tab navigation for the app
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "mountain.2.fill" : "mountain.2")
                    Text("My Crags")
                }
                .tag(0)

            AreaBrowserView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "binoculars.fill" : "binoculars")
                    Text("Discover")
                }
                .tag(1)
        }
        .tint(.climbRope)
        .onAppear {
            configureTabBarAppearance()
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.white)

        // Selected state
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.climbRope)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.climbRope),
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        // Normal state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color.climbStone)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.climbStone),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
        .environmentObject(CragStore())
}
