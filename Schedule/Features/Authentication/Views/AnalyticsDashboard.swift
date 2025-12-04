//
//  AnalyticsDashboard.swift
//  Schedule
//
//  Proper implementation with color theming - FIXED
//

import SwiftUI

struct AnalyticsDashboard: View {
    @EnvironmentObject var analyticsManager: AnalyticsManager
    @Environment(\.dismiss) var dismiss
    
    // Theme colors - optional with defaults
    let primaryColor: Color
    let secondaryColor: Color
    let tertiaryColor: Color
    
    @State private var selectedPeriod: String = "Daily"
    let periods = ["Daily", "Weekly", "Monthly"]
    @State private var showResetAlert = false
    
    // MARK: - Init with default colors
    init(
        PrimaryColor: Color = .blue,
        SecondaryColor: Color = .gray,
        TertiaryColor: Color = .orange
    ) {
        self.primaryColor = PrimaryColor
        self.secondaryColor = SecondaryColor
        self.tertiaryColor = TertiaryColor
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(primaryColor)
                    }
                    
                    Spacer()
                    
                    Text("Analytics")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Invisible spacer for centering
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.clear)
                }
                .padding()
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 1)
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Period Selector
                        Picker("Period", selection: $selectedPeriod) {
                            ForEach(periods, id: \.self) { period in
                                Text(period).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        // Key Metrics
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                MetricCardView(
                                    title: "DAU",
                                    value: analyticsManager.dailyAnalytics?.uniqueUsers.count ?? 0,
                                    icon: "person.fill",
                                    color: primaryColor
                                )
                                
                                MetricCardView(
                                    title: "WAU",
                                    value: analyticsManager.weeklyDAU,
                                    icon: "calendar.circle.fill",
                                    color: secondaryColor
                                )
                                
                                MetricCardView(
                                    title: "MAU",
                                    value: analyticsManager.monthlyDAU,
                                    icon: "chart.bar.fill",
                                    color: tertiaryColor
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Session Statistics
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Session Statistics")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .padding(.horizontal)
                            
                            if let analytics = analyticsManager.dailyAnalytics {
                                VStack(spacing: 0) {
                                    StatRowView(
                                        label: "Total Sessions",
                                        value: "\(analytics.totalSessions)",
                                        icon: "circle.fill",
                                        color: primaryColor
                                    )
                                    
                                    Divider()
                                        .padding(.horizontal)
                                    
                                    StatRowView(
                                        label: "App Launches",
                                        value: "\(analytics.totalAppLaunches)",
                                        icon: "arrowshape.up.fill",
                                        color: secondaryColor
                                    )
                                    
                                    Divider()
                                        .padding(.horizontal)
                                    
                                    StatRowView(
                                        label: "Avg Duration",
                                        value: formatDuration(analytics.averageSessionDuration),
                                        icon: "timer.circle.fill",
                                        color: tertiaryColor
                                    )
                                }
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                        }
                        
                        // Top Features
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Features")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .padding(.horizontal)
                            
                            let topFeatures = analyticsManager.getTopFeatures()
                            
                            if topFeatures.isEmpty {
                                Text("No data yet")
                                    .foregroundColor(.gray)
                                    .padding(.horizontal)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(topFeatures.enumerated()), id: \.offset) { index, feature in
                                        FeatureRowView(
                                            rank: index + 1,
                                            name: feature.0,
                                            count: feature.1,
                                            color: primaryColor
                                        )
                                        
                                        if index < topFeatures.count - 1 {
                                            Divider()
                                                .padding(.horizontal)
                                        }
                                    }
                                }
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                        }
                        
                        // Current Session
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Session")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .padding(.horizontal)
                            
                            VStack(alignment: .center, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "timer.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(primaryColor)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Session Duration")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Text(formatDuration(analyticsManager.currentSessionDuration))
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Export Button
                        Button(action: exportAnalytics) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export Analytics")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(primaryColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        
                        // Refresh Button
                        Button(action: refreshAnalytics) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Data")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(secondaryColor.opacity(0.2))
                            .foregroundColor(secondaryColor)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Reset Button
                        Button(role: .destructive, action: { showResetAlert = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                Text("Reset Analytics")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                            .frame(height: 20)
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .onAppear {
            analyticsManager.trackScreenView("AnalyticsDashboard")
        }
        .alert("Reset All Analytics?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                analyticsManager.resetAllAnalytics()
                analyticsManager.trackButtonTap("AnalyticsDashboard.ResetButton")
            }
        } message: {
            Text("This will permanently delete all analytics data. This action cannot be undone.")
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func exportAnalytics() {
        analyticsManager.trackButtonTap("AnalyticsDashboard.ExportButton")
        
        if let json = analyticsManager.exportAnalyticsAsJSON() {
            UIPasteboard.general.string = json
            print("✅ Analytics exported to clipboard")
        }
    }
    
    private func refreshAnalytics() {
        analyticsManager.trackButtonTap("AnalyticsDashboard.RefreshButton")
        analyticsManager.loadAnalytics()
    }
}

// MARK: - Helper Components

struct MetricCardView: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .fontWeight(.medium)
            
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct StatRowView: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(label)
                .foregroundColor(.gray)
                .font(.body)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding()
    }
}

struct FeatureRowView: View {
    let rank: Int
    let name: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(name)
                .lineLimit(2)
                .foregroundColor(.primary)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(count)")
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("times")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AnalyticsDashboard(
            PrimaryColor: .blue,
            SecondaryColor: .gray,
            TertiaryColor: .orange
        )
        .environmentObject(AnalyticsManager())
    }
}
