//
//  ForecastView.swift
//  CLIMB.it
//
//  14-day weather forecast with predicted safety statuses
//

import SwiftUI

struct ForecastView: View {
    let crag: Crag
    @State private var forecast: CragForecast?
    @State private var isLoading = true
    @State private var error: String?
    @AppStorage("useImperialUnits") private var useImperialUnits = true

    var body: some View {
        ZStack {
            Color.climbChalk.ignoresSafeArea()

            if isLoading {
                VStack(spacing: ClimbSpacing.md) {
                    ProgressView()
                    Text("Loading forecast...")
                        .font(ClimbTypography.caption)
                        .foregroundColor(.climbStone)
                }
            } else if let error = error {
                VStack(spacing: ClimbSpacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.climbCaution)
                    Text(error)
                        .font(ClimbTypography.body)
                        .foregroundColor(.climbStone)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadForecast() }
                    }
                    .foregroundColor(.climbRope)
                }
                .padding()
            } else if let forecast = forecast {
                ScrollView {
                    VStack(spacing: ClimbSpacing.lg) {
                        // Header with current status
                        headerSection

                        // Estimated safe date banner
                        if crag.safetyStatus != .safe, let safeDate = forecast.estimatedSafeDateFormatted {
                            safeDateBanner(safeDate)
                        }

                        // Daily forecast cards
                        LazyVStack(spacing: ClimbSpacing.md) {
                            ForEach(forecast.days) { day in
                                forecastDayRow(day: day)
                            }
                        }
                    }
                    .padding(ClimbSpacing.md)
                    .padding(.bottom, ClimbSpacing.xxl)
                }
            }
        }
        .navigationTitle("14-Day Forecast")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                unitToggle
            }
        }
        .task {
            await loadForecast()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: ClimbSpacing.sm) {
            Text(crag.name)
                .font(ClimbTypography.title2)
                .foregroundColor(.climbGranite)

            HStack(spacing: ClimbSpacing.sm) {
                Circle()
                    .fill(statusColor(for: crag.safetyStatus))
                    .frame(width: 10, height: 10)
                Text("Currently \(crag.safetyStatus.displayName)")
                    .font(ClimbTypography.caption)
                    .foregroundColor(.climbStone)
            }
        }
        .padding(.bottom, ClimbSpacing.sm)
    }

    // MARK: - Safe Date Banner

    private func safeDateBanner(_ safeDate: String) -> some View {
        HStack(spacing: ClimbSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.climbSafe)
            VStack(alignment: .leading, spacing: 2) {
                Text("Expected safe")
                    .font(ClimbTypography.micro)
                    .foregroundColor(.climbStone)
                Text(safeDate)
                    .font(ClimbTypography.bodyBold)
                    .foregroundColor(.climbSafe)
            }
            Spacer()
        }
        .padding(ClimbSpacing.md)
        .background(Color.climbSafe.opacity(0.1))
        .cornerRadius(ClimbRadius.medium)
    }

    // MARK: - Forecast Day Row

    private func forecastDayRow(day: DayForecast) -> some View {
        HStack(spacing: ClimbSpacing.md) {
            // Date column
            VStack(alignment: .leading, spacing: 2) {
                Text(day.dayOfWeek)
                    .font(ClimbTypography.captionBold)
                    .foregroundColor(.climbGranite)
                Text(day.dayOfMonth)
                    .font(ClimbTypography.title3)
                    .foregroundColor(.climbGranite)
            }
            .frame(width: 44)

            // Weather icon
            Image(systemName: day.weatherIcon)
                .font(.system(size: 28))
                .foregroundColor(day.precipitationMm > 1 ? .climbRope : .climbSandstone)
                .frame(width: 40)

            // Temperature
            VStack(alignment: .leading, spacing: 2) {
                if let high = day.tempHighC, let low = day.tempLowC {
                    let displayHigh = useImperialUnits ? celsiusToFahrenheit(high) : high
                    let displayLow = useImperialUnits ? celsiusToFahrenheit(low) : low
                    Text("\(Int(displayHigh))°")
                        .font(ClimbTypography.bodyBold)
                        .foregroundColor(.climbGranite)
                    Text("\(Int(displayLow))°")
                        .font(ClimbTypography.caption)
                        .foregroundColor(.climbStone)
                }
            }
            .frame(width: 40)

            // Precipitation
            VStack(alignment: .leading, spacing: 2) {
                let displayPrecip = useImperialUnits ? mmToInches(day.precipitationMm) : day.precipitationMm
                let unit = useImperialUnits ? "in" : "mm"
                let format = useImperialUnits ? "%.2f" : "%.1f"

                if day.precipitationMm > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.climbRope)
                        Text("\(String(format: format, displayPrecip)) \(unit)")
                            .font(ClimbTypography.caption)
                            .foregroundColor(.climbRope)
                    }
                } else {
                    Text("No rain")
                        .font(ClimbTypography.caption)
                        .foregroundColor(.climbStone)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(statusColor(for: day.predictedStatus))
                    .frame(width: 16, height: 16)
                Text(day.predictedStatus.displayName)
                    .font(ClimbTypography.micro)
                    .foregroundColor(statusColor(for: day.predictedStatus))
            }
            .frame(width: 60)
        }
        .padding(ClimbSpacing.md)
        .background(statusColor(for: day.predictedStatus).opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: ClimbRadius.medium)
                .stroke(statusColor(for: day.predictedStatus).opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(ClimbRadius.medium)
    }

    // MARK: - Unit Toggle

    private var unitToggle: some View {
        Menu {
            Button(action: { useImperialUnits = true }) {
                Label("Imperial (°F, in)", systemImage: useImperialUnits ? "checkmark" : "")
            }
            Button(action: { useImperialUnits = false }) {
                Label("Metric (°C, mm)", systemImage: useImperialUnits ? "" : "checkmark")
            }
        } label: {
            Text(useImperialUnits ? "°F" : "°C")
                .font(ClimbTypography.captionBold)
                .foregroundColor(.climbRope)
                .padding(.horizontal, ClimbSpacing.sm)
                .padding(.vertical, ClimbSpacing.xs)
                .background(Color.climbRope.opacity(0.1))
                .cornerRadius(ClimbRadius.small)
        }
    }

    // MARK: - Helpers

    private func statusColor(for status: Crag.SafetyStatus) -> Color {
        switch status {
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        case .unknown: return .climbUnknown
        }
    }

    private func celsiusToFahrenheit(_ celsius: Double) -> Double {
        celsius * 9 / 5 + 32
    }

    private func mmToInches(_ mm: Double) -> Double {
        mm / 25.4
    }

    private func loadForecast() async {
        isLoading = true
        error = nil

        do {
            forecast = try await APIClient.shared.getForecast(cragId: crag.id, days: 14)
        } catch {
            self.error = "Unable to load forecast. Please try again."
            print("Forecast error: \(error)")
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        ForecastView(crag: .preview)
    }
}
