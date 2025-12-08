//
//  OnboardingView.swift
//  CLIMB.it
//
//  Welcome flow for new users
//

import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "mountain.2.fill",
            iconColors: [.climbSandstone, .climbGranite],
            title: "Welcome to",
            subtitle: nil,
            description: "Your personal climbing conditions companion"
        ),
        OnboardingPage(
            icon: "cloud.sun.rain.fill",
            iconColors: [.climbRope, .climbSafe],
            title: "Real-Time Weather",
            subtitle: "Data at your fingertips",
            description: "Track precipitation and know when rock conditions are safe for climbing"
        ),
        OnboardingPage(
            icon: "bookmark.fill",
            iconColors: [.climbSandstone, .climbCaution],
            title: "Save Your Spots",
            subtitle: nil,
            description: "Build a personal list of your favorite crags and monitor conditions at a glance"
        ),
        OnboardingPage(
            icon: "checkmark.shield.fill",
            iconColors: [.climbSafe, .climbRope],
            title: "Know Before You Go",
            subtitle: nil,
            description: "Make informed decisions and protect the rock you love"
        )
    ]

    var body: some View {
        ZStack {
            // Background
            Color.climbChalk.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(
                            page: pages[index],
                            showLogo: index == 0
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Bottom controls
                bottomControls
                    .padding(.horizontal, ClimbSpacing.lg)
                    .padding(.bottom, ClimbSpacing.xxl)
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: ClimbSpacing.lg) {
            // Page indicators
            HStack(spacing: ClimbSpacing.sm) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.climbRope : Color.climbMist)
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            // Action buttons
            if currentPage == pages.count - 1 {
                // Last page - Get Started button
                ClimbButton("Get Started", icon: "arrow.right") {
                    withAnimation {
                        hasCompletedOnboarding = true
                    }
                }
            } else {
                // Continue button
                HStack(spacing: ClimbSpacing.md) {
                    // Skip button
                    Button("Skip") {
                        withAnimation {
                            hasCompletedOnboarding = true
                        }
                    }
                    .font(ClimbTypography.bodyBold)
                    .foregroundColor(.climbStone)
                    .frame(maxWidth: .infinity)

                    // Next button
                    ClimbButton("Next", icon: "arrow.right") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let icon: String
    let iconColors: [Color]
    let title: String
    let subtitle: String?
    let description: String
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    let showLogo: Bool

    var body: some View {
        VStack(spacing: ClimbSpacing.xl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: page.iconColors.map { $0.opacity(0.15) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: page.iconColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 48))
                    .foregroundColor(.white)
            }

            // Text content
            VStack(spacing: ClimbSpacing.md) {
                if showLogo {
                    // Special treatment for first page
                    Text(page.title)
                        .font(ClimbTypography.title2)
                        .foregroundColor(.climbStone)

                    ClimbLogo(size: .large)

                    ClimbTagline()
                        .padding(.top, ClimbSpacing.sm)
                } else {
                    // Regular page
                    VStack(spacing: ClimbSpacing.xs) {
                        Text(page.title)
                            .font(ClimbTypography.title1)
                            .foregroundColor(.climbGranite)

                        if let subtitle = page.subtitle {
                            Text(subtitle)
                                .font(ClimbTypography.title3)
                                .foregroundColor(.climbSandstone)
                        }
                    }
                }

                Text(page.description)
                    .font(ClimbTypography.body)
                    .foregroundColor(.climbStone)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, ClimbSpacing.lg)
            }

            Spacer()
            Spacer()
        }
        .padding(ClimbSpacing.lg)
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
