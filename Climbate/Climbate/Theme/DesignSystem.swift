//
//  DesignSystem.swift
//  CLIMB.it
//
//  Design system for CLIMB.it - "Know before you go"
//  Adventure/outdoorsy meets minimal/modern
//

import SwiftUI

// MARK: - Brand Colors

extension Color {
    // Primary palette - Earthy adventure tones
    static let climbGranite = Color(hex: "2D3436")      // Deep charcoal - primary text
    static let climbSandstone = Color(hex: "D4A574")    // Warm sandstone - accent
    static let climbChalk = Color(hex: "F5F1EB")        // Off-white chalk - backgrounds
    static let climbRope = Color(hex: "0984E3")         // Climbing rope blue - interactive

    // Safety status colors (darkened for readability)
    static let climbSafe = Color(hex: "00966D")         // Deep green
    static let climbCaution = Color(hex: "D4930D")      // Rich amber
    static let climbUnsafe = Color(hex: "C0392B")       // Bold red
    static let climbUnknown = Color(hex: "636E72")      // Gray for unknown

    // Supporting colors
    static let climbMist = Color(hex: "DFE6E9")         // Light gray for cards
    static let climbStone = Color(hex: "636E72")        // Medium gray for secondary text
    static let climbShadow = Color(hex: "2D3436").opacity(0.1)

    // Gradient backgrounds
    static let climbGradientStart = Color(hex: "74B9FF")
    static let climbGradientEnd = Color(hex: "0984E3")
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography

struct ClimbTypography {
    // Display - Hero headers
    static let heroTitle = Font.system(size: 34, weight: .bold, design: .rounded)

    // Headlines
    static let title1 = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let title3 = Font.system(size: 20, weight: .semibold, design: .default)

    // Body text
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let bodyBold = Font.system(size: 15, weight: .semibold, design: .default)

    // Captions and labels
    static let caption = Font.system(size: 13, weight: .regular, design: .default)
    static let captionBold = Font.system(size: 13, weight: .semibold, design: .default)
    static let micro = Font.system(size: 11, weight: .medium, design: .default)
}

// MARK: - Spacing

struct ClimbSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius

struct ClimbRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let pill: CGFloat = 100
}

// MARK: - Shadows

extension View {
    func climbCardShadow() -> some View {
        self.shadow(color: .climbShadow, radius: 8, x: 0, y: 4)
    }

    func climbSubtleShadow() -> some View {
        self.shadow(color: .climbShadow, radius: 4, x: 0, y: 2)
    }
}

// MARK: - Reusable Components

struct ClimbCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(ClimbSpacing.md)
            .background(Color.white)
            .cornerRadius(ClimbRadius.large)
            .climbCardShadow()
    }
}

struct ClimbButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
        case ghost
    }

    init(_ title: String, icon: String? = nil, style: ButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ClimbSpacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(ClimbTypography.bodyBold)
            }
            .padding(.horizontal, ClimbSpacing.lg)
            .padding(.vertical, ClimbSpacing.md)
            .frame(maxWidth: style == .ghost ? nil : .infinity)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(ClimbRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: ClimbRadius.medium)
                    .stroke(borderColor, lineWidth: style == .secondary ? 2 : 0)
            )
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return .climbRope
        case .secondary: return .clear
        case .ghost: return .clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return .climbRope
        case .ghost: return .climbRope
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary: return .climbRope
        default: return .clear
        }
    }
}

// MARK: - Status Badge Component

struct ClimbStatusBadge: View {
    let status: Crag.SafetyStatus
    let size: BadgeSize

    enum BadgeSize {
        case small
        case medium
        case large
    }

    init(_ status: Crag.SafetyStatus, size: BadgeSize = .medium) {
        self.status = status
        self.size = size
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: dotSize, height: dotSize)

            Text(status.displayName.uppercased())
                .font(textFont)
                .fontWeight(.bold)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(statusColor.opacity(0.15))
        .cornerRadius(ClimbRadius.pill)
    }

    private var statusColor: Color {
        switch status {
        case .safe: return .climbSafe
        case .caution: return .climbCaution
        case .unsafe: return .climbUnsafe
        case .unknown: return .climbUnknown
        }
    }

    private var dotSize: CGFloat {
        switch size {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        }
    }

    private var textFont: Font {
        switch size {
        case .small: return ClimbTypography.micro
        case .medium: return ClimbTypography.captionBold
        case .large: return ClimbTypography.bodyBold
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return 8
        case .medium: return 12
        case .large: return 16
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .small: return 4
        case .medium: return 6
        case .large: return 8
        }
    }
}

// MARK: - Weather Indicator

struct WeatherIndicator: View {
    let precipitation: Crag.PrecipitationData?

    var body: some View {
        HStack(spacing: ClimbSpacing.sm) {
            Image(systemName: precipitationIcon)
                .foregroundColor(.climbRope)

            if let precip = precipitation {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(String(format: "%.1f", precip.last7DaysMm))mm")
                        .font(ClimbTypography.captionBold)
                        .foregroundColor(.climbGranite)

                    if let days = precip.daysSinceRain {
                        Text("\(days)d since rain")
                            .font(ClimbTypography.micro)
                            .foregroundColor(.climbStone)
                    }
                }
            } else {
                Text("No data")
                    .font(ClimbTypography.caption)
                    .foregroundColor(.climbStone)
            }
        }
        .padding(ClimbSpacing.sm)
        .background(Color.climbMist)
        .cornerRadius(ClimbRadius.small)
    }

    private var precipitationIcon: String {
        guard let precip = precipitation else { return "cloud.fill" }
        if precip.last7DaysMm == 0 {
            return "sun.max.fill"
        } else if precip.last7DaysMm < 10 {
            return "cloud.sun.fill"
        } else {
            return "cloud.rain.fill"
        }
    }
}

// MARK: - App Logo

struct ClimbLogo: View {
    let size: LogoSize

    enum LogoSize {
        case small   // 24pt - nav bars
        case medium  // 40pt - cards
        case large   // 80pt - splash/onboarding
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("CLIMB")
                .font(logoFont)
                .fontWeight(.black)
                .foregroundColor(.climbGranite)
            Text(".")
                .font(logoFont)
                .fontWeight(.black)
                .foregroundColor(.climbSandstone)
            Text("it")
                .font(logoFont)
                .fontWeight(.light)
                .foregroundColor(.climbGranite)
        }
    }

    private var logoFont: Font {
        switch size {
        case .small: return .system(size: 18, design: .rounded)
        case .medium: return .system(size: 28, design: .rounded)
        case .large: return .system(size: 48, design: .rounded)
        }
    }
}

// MARK: - Tagline

struct ClimbTagline: View {
    var body: some View {
        Text("Know before you go")
            .font(ClimbTypography.caption)
            .fontWeight(.medium)
            .foregroundColor(.climbStone)
            .tracking(1.5)
    }
}
