//
//  CragDetailView.swift
//  CLIMB.it
//
//  Detailed view of a climbing area with weather conditions
//

import SwiftUI
import MapKit

struct CragDetailView: View {
    let crag: Crag
    @EnvironmentObject var cragStore: CragStore
    @State private var detailedCrag: Crag?
    @AppStorage("useImperialUnits") private var useImperialUnits = true

    var displayCrag: Crag {
        detailedCrag ?? crag
    }

    var body: some View {
        ZStack {
            Color.climbChalk.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero header with status
                    heroHeader

                    // Content
                    VStack(spacing: ClimbSpacing.lg) {
                        // Status message (only show for non-safe statuses)
                        if displayCrag.safetyStatus != .safe {
                            statusCard
                        }

                        // Weather card (navigates to forecast page)
                        weatherCard

                        // Quick actions
                        actionsCard

                        // Location links
                        linksCard
                    }
                    .padding(ClimbSpacing.md)
                    .padding(.bottom, ClimbSpacing.xxl)
                }
            }
            .refreshable {
                detailedCrag = await cragStore.refreshCragDetails(crag)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(displayCrag.name)
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { cragStore.toggle(displayCrag) }) {
                    Image(systemName: cragStore.isSaved(displayCrag) ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                        .foregroundColor(cragStore.isSaved(displayCrag) ? .climbSandstone : .climbStone)
                }
            }
        }
        .task {
            detailedCrag = await cragStore.refreshCragDetails(crag)
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: ClimbSpacing.md) {
            // Status circle
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(statusColor)
                    .frame(width: 80, height: 80)

                Image(systemName: statusIcon)
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }

            // Status text
            VStack(spacing: ClimbSpacing.xs) {
                Text(displayCrag.safetyStatus.displayName.uppercased())
                    .font(ClimbTypography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(statusColor)

                Text(statusSubtitle)
                    .font(ClimbTypography.caption)
                    .foregroundColor(.climbStone)
            }

            // Location breadcrumb
            Text(displayCrag.location)
                .font(ClimbTypography.caption)
                .foregroundColor(.climbStone)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ClimbSpacing.lg)
        }
        .padding(.vertical, ClimbSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [statusColor.opacity(0.05), Color.climbChalk],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var statusIcon: String {
        switch displayCrag.safetyStatus {
        case .safe: return "checkmark"
        case .caution: return "exclamationmark"
        case .unsafe: return "xmark"
        case .unknown: return "questionmark"
        }
    }

    private var statusSubtitle: String {
        switch displayCrag.safetyStatus {
        case .safe: return "Good to climb"
        case .caution: return "Check conditions"
        case .unsafe: return "Rock may be wet"
        case .unknown: return "No weather data"
        }
    }

    private var statusColor: Color {
        switch displayCrag.safetyStatus {
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        case .unknown: return .climbUnknown
        }
    }

    // MARK: - Weather Card

    private var weatherCard: some View {
        NavigationLink(destination: ForecastView(crag: displayCrag)) {
            VStack(alignment: .leading, spacing: ClimbSpacing.md) {
                HStack {
                    Image(systemName: "cloud.sun.fill")
                        .foregroundColor(.climbRope)
                    Text("Weather Data")
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)

                    Spacer()

                    // Navigate to forecast indicator
                    HStack(spacing: 4) {
                        Text("14-Day Forecast")
                            .font(ClimbTypography.caption)
                            .foregroundColor(.climbRope)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.climbRope)
                    }
                }

                if let precip = displayCrag.precipitation {
                    HStack(spacing: ClimbSpacing.md) {
                        // Precipitation gauge
                        precipitationGauge(value: precip.last7DaysMm)

                        Divider()
                            .frame(height: 60)

                        // Days since rain
                        if let days = precip.daysSinceRain {
                            daysSinceRainView(days: days)
                        } else {
                            VStack {
                                Text("--")
                                    .font(ClimbTypography.title1)
                                    .foregroundColor(.climbGranite)
                                Text("days dry")
                                    .font(ClimbTypography.micro)
                                    .foregroundColor(.climbStone)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.climbCaution)
                        Text("Weather data unavailable")
                            .font(ClimbTypography.body)
                            .foregroundColor(.climbStone)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ClimbSpacing.md)
                }
            }
            .padding(ClimbSpacing.md)
            .background(Color.white)
            .cornerRadius(ClimbRadius.large)
            .climbCardShadow()
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func precipitationGauge(value: Double) -> some View {
        let displayValue = useImperialUnits ? mmToInches(value) : value
        let unitLabel = useImperialUnits ? "in" : "mm"
        let formatString = useImperialUnits ? "%.2f" : "%.1f"

        return VStack(spacing: ClimbSpacing.sm) {
            // Circular gauge
            ZStack {
                Circle()
                    .stroke(Color.climbMist, lineWidth: 8)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0, to: min(value / 50, 1)) // 50mm max
                    .stroke(precipColor(for: value), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "drop.fill")
                    .font(.system(size: 20))
                    .foregroundColor(precipColor(for: value))
            }

            VStack(spacing: 2) {
                Text("\(String(format: formatString, displayValue))")
                    .font(ClimbTypography.title3)
                    .foregroundColor(.climbGranite)
                Text("\(unitLabel) / 7 days")
                    .font(ClimbTypography.micro)
                    .foregroundColor(.climbStone)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func precipColor(for value: Double) -> Color {
        if value == 0 { return .climbSafe }
        if value < 10 { return .climbCaution }
        return .climbUnsafe
    }

    private func daysSinceRainView(days: Int) -> some View {
        VStack(spacing: ClimbSpacing.sm) {
            ZStack {
                Circle()
                    .fill(daysColor(for: days).opacity(0.15))
                    .frame(width: 60, height: 60)

                Text("\(days)")
                    .font(ClimbTypography.title1)
                    .foregroundColor(daysColor(for: days))
            }

            VStack(spacing: 2) {
                Text(days == 1 ? "day" : "days")
                    .font(ClimbTypography.caption)
                    .foregroundColor(.climbGranite)
                Text("since rain")
                    .font(ClimbTypography.micro)
                    .foregroundColor(.climbStone)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func daysColor(for days: Int) -> Color {
        if days >= 3 { return .climbSafe }
        if days >= 1 { return .climbCaution }
        return .climbUnsafe
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: ClimbSpacing.md) {
            statusMessage
        }
        .padding(ClimbSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.1))
        .cornerRadius(ClimbRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: ClimbRadius.large)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch displayCrag.safetyStatus {
        case .unsafe:
            unsafeMessage
        case .caution:
            cautionMessage
        case .safe:
            safeMessage
        case .unknown:
            unknownMessage
        }
    }

    private var unsafeMessage: some View {
        VStack(alignment: .leading, spacing: ClimbSpacing.sm) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.climbUnsafe)
                Text("Not Recommended")
                    .font(ClimbTypography.bodyBold)
                    .foregroundColor(.climbUnsafe)
            }

            if let precip = displayCrag.precipitation, let days = precip.daysSinceRain {
                Text("Rain \(days) day\(days == 1 ? "" : "s") ago with \(String(format: "%.1f", precip.last7DaysMm))mm this week. Rock is likely still wet.")
                    .font(ClimbTypography.body)
                    .foregroundColor(.climbGranite)
            } else {
                Text("Recent precipitation has made conditions unsafe for climbing.")
                    .font(ClimbTypography.body)
                    .foregroundColor(.climbGranite)
            }

            NavigationLink(destination: AlternateAdventureView(sourceCrag: displayCrag)) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                    Text("Find Alternate Adventures")
                }
                .font(ClimbTypography.captionBold)
                .foregroundColor(.climbRope)
            }
            .padding(.top, ClimbSpacing.xs)
        }
    }

    private var cautionMessage: some View {
        VStack(alignment: .leading, spacing: ClimbSpacing.sm) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.climbCaution)
                Text("Exercise Caution")
                    .font(ClimbTypography.bodyBold)
                    .foregroundColor(.climbCaution)
            }

            Text("Conditions are variable. Check local reports and inspect the rock before committing to a route.")
                .font(ClimbTypography.body)
                .foregroundColor(.climbGranite)

            NavigationLink(destination: AlternateAdventureView(sourceCrag: displayCrag)) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                    Text("Find Alternate Adventures")
                }
                .font(ClimbTypography.captionBold)
                .foregroundColor(.climbRope)
            }
            .padding(.top, ClimbSpacing.xs)
        }
    }

    private var safeMessage: some View {
        VStack(alignment: .leading, spacing: ClimbSpacing.sm) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.climbSafe)
                Text("Good Conditions")
                    .font(ClimbTypography.bodyBold)
                    .foregroundColor(.climbSafe)
            }

            if let precip = displayCrag.precipitation, let days = precip.daysSinceRain {
                Text("No rain for \(days) day\(days == 1 ? "" : "s"). The rock should be dry and ready for climbing!")
                    .font(ClimbTypography.body)
                    .foregroundColor(.climbGranite)
            } else {
                Text("Conditions look good for climbing. Enjoy your session!")
                    .font(ClimbTypography.body)
                    .foregroundColor(.climbGranite)
            }
        }
    }

    private var unknownMessage: some View {
        VStack(alignment: .leading, spacing: ClimbSpacing.sm) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.climbUnknown)
                Text("No Weather Data")
                    .font(ClimbTypography.bodyBold)
                    .foregroundColor(.climbUnknown)
            }

            Text("Weather data is not yet available for this area. Check local conditions before climbing.")
                .font(ClimbTypography.body)
                .foregroundColor(.climbGranite)

            NavigationLink(destination: AlternateAdventureView(sourceCrag: displayCrag)) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                    Text("Find Alternate Adventures")
                }
                .font(ClimbTypography.captionBold)
                .foregroundColor(.climbRope)
            }
            .padding(.top, ClimbSpacing.xs)
        }
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        HStack(spacing: ClimbSpacing.md) {
            actionButton(
                icon: "bookmark",
                filledIcon: "bookmark.fill",
                label: cragStore.isSaved(displayCrag) ? "Saved" : "Save",
                isActive: cragStore.isSaved(displayCrag)
            ) {
                cragStore.toggle(displayCrag)
            }

            actionButton(
                icon: "arrow.clockwise",
                filledIcon: "arrow.clockwise",
                label: "Refresh",
                isActive: false
            ) {
                Task {
                    detailedCrag = await cragStore.refreshCragDetails(crag)
                }
            }

            actionButton(
                icon: "square.and.arrow.up",
                filledIcon: "square.and.arrow.up.fill",
                label: "Share",
                isActive: false
            ) {
                // Share functionality
            }
        }
    }

    private func actionButton(icon: String, filledIcon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: ClimbSpacing.sm) {
                Image(systemName: isActive ? filledIcon : icon)
                    .font(.title2)
                    .foregroundColor(isActive ? .climbSandstone : .climbRope)

                Text(label)
                    .font(ClimbTypography.micro)
                    .foregroundColor(.climbStone)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ClimbSpacing.md)
            .background(Color.white)
            .cornerRadius(ClimbRadius.medium)
            .climbSubtleShadow()
        }
    }

    // MARK: - Links Card

    private var linksCard: some View {
        VStack(spacing: ClimbSpacing.sm) {
            linkButton(
                icon: "map.fill",
                title: "Apple Maps",
                subtitle: "Get directions",
                color: .climbSafe,
                url: appleMapsURL
            )

            linkButton(
                icon: "location.fill",
                title: "Google Maps",
                subtitle: "Get directions",
                color: .climbRope,
                url: googleMapsURL
            )

            if let mpUrl = displayCrag.mountainProjectUrl, let url = URL(string: mpUrl) {
                linkButton(
                    icon: "mountain.2.fill",
                    title: "Mountain Project",
                    subtitle: "View routes & beta",
                    color: .climbSandstone,
                    url: url
                )
            }
        }
    }

    private func linkButton(icon: String, title: String, subtitle: String, color: Color, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: ClimbSpacing.md) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)
                    Text(subtitle)
                        .font(ClimbTypography.micro)
                        .foregroundColor(.climbStone)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.climbStone)
            }
            .padding(ClimbSpacing.md)
            .background(Color.white)
            .cornerRadius(ClimbRadius.medium)
            .climbSubtleShadow()
        }
    }

    // MARK: - Unit Conversions

    private func mmToInches(_ mm: Double) -> Double {
        mm / 25.4
    }

    // MARK: - URLs

    private var googleMapsURL: URL {
        URL(string: "https://www.google.com/maps?q=\(displayCrag.latitude),\(displayCrag.longitude)")!
    }

    private var appleMapsURL: URL {
        URL(string: "http://maps.apple.com/?q=\(displayCrag.latitude),\(displayCrag.longitude)")!
    }
}

#Preview("Safe Crag") {
    NavigationStack {
        CragDetailView(crag: .preview)
            .environmentObject(CragStore())
    }
}

#Preview("Unsafe Crag") {
    NavigationStack {
        CragDetailView(crag: .previewUnsafe)
            .environmentObject(CragStore())
    }
}
