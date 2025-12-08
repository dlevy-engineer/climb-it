//
//  ClimbateApp.swift
//  CLIMB.it
//
//  "Know before you go" - Climbing conditions at a glance
//

import SwiftUI

@main
struct ClimbateApp: App {
    @StateObject private var cragStore = CragStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(cragStore)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(cragStore)
            }
        }
    }
}
