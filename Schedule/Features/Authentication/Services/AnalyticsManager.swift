//
//  AnalyticsManager.swift - FIXED
//  Schedule
//
//  Properly tracks DAU (one per user per day, not per app open)
//

import Foundation
import FirebaseFirestore

// MARK: - Models

struct UserSession: Codable {
    let sessionId: UUID
    let userId: String
    let date: Date
    let timestamp: Date
    let appVersion: String
    let osVersion: String
    let deviceModel: String
}

struct DailyAnalytics: Codable {
    var date: Date
    var uniqueUsers: Set<String>
    var totalSessions: Int
    var totalAppLaunches: Int
    var averageSessionDuration: TimeInterval
    var featureUsage: [String: Int]
    
    init(date: Date, uniqueUsers: Set<String> = [], totalSessions: Int = 0, totalAppLaunches: Int = 0, averageSessionDuration: TimeInterval = 0, featureUsage: [String: Int] = [:]) {
        self.date = date
        self.uniqueUsers = uniqueUsers
        self.totalSessions = totalSessions
        self.totalAppLaunches = totalAppLaunches
        self.averageSessionDuration = averageSessionDuration
        self.featureUsage = featureUsage
    }
    
    enum CodingKeys: String, CodingKey {
        case date
        case uniqueUsers
        case totalSessions
        case totalAppLaunches
        case averageSessionDuration
        case featureUsage
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        uniqueUsers = Set(try container.decode([String].self, forKey: .uniqueUsers))
        totalSessions = try container.decode(Int.self, forKey: .totalSessions)
        totalAppLaunches = try container.decode(Int.self, forKey: .totalAppLaunches)
        averageSessionDuration = try container.decode(TimeInterval.self, forKey: .averageSessionDuration)
        featureUsage = try container.decode([String: Int].self, forKey: .featureUsage)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(Array(uniqueUsers), forKey: .uniqueUsers)
        try container.encode(totalSessions, forKey: .totalSessions)
        try container.encode(totalAppLaunches, forKey: .totalAppLaunches)
        try container.encode(averageSessionDuration, forKey: .averageSessionDuration)
        try container.encode(featureUsage, forKey: .featureUsage)
    }
}

struct AnalyticsSnapshot: Codable {
    var dau: Int
    var wau: Int
    var mau: Int
    var totalSessions: Int
    var averageSessionDuration: TimeInterval
    var topFeatures: [String: Int]
    var timestamp: Date
}

// MARK: - Analytics Manager

class AnalyticsManager: NSObject, ObservableObject {
    @Published var dailyAnalytics: DailyAnalytics?
    @Published var weeklyDAU: Int = 0
    @Published var monthlyDAU: Int = 0
    @Published var currentSessionDuration: TimeInterval = 0
    
    private let userDefaults = UserDefaults.standard
    private lazy var firestore = Firestore.firestore()
    
    private var sessionStartTime: Date?
    private var currentSessionId: UUID = UUID()
    private var sessionTimer: Timer?
    private var userId: String?
    
    private let dailyAnalyticsKey = "DailyAnalytics_"
    private let userIdKey = "AnalyticsUserId"
    private let lastSessionDateKey = "LastSessionDate"  // ← NEW: Track last session date
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupUserId()
        loadAnalytics()
        // ✅ Auto-start session when manager is created
        startSession()
    }
    
    deinit {
        endSession()
        sessionTimer?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setupUserId() {
        if let savedUserId = userDefaults.string(forKey: userIdKey) {
            self.userId = savedUserId
        } else {
            let newUserId = UUID().uuidString
            userDefaults.set(newUserId, forKey: userIdKey)
            self.userId = newUserId
        }
    }
    
    // MARK: - Session Management
    
    func startSession() {
        guard sessionStartTime == nil else { return }
        
        sessionStartTime = Date()
        currentSessionId = UUID()
        
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateSessionDuration()
        }
        
        // ✅ FIXED: Only count user once per day, not per app open
        logSessionStart()
    }
    
    func endSession() {
        guard let startTime = sessionStartTime, let userId = userId else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        let session = UserSession(
            sessionId: currentSessionId,
            userId: userId,
            date: startTime,
            timestamp: Date(),
            appVersion: Bundle.main.appVersion,
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.modelName
        )
        
        saveSession(session, duration: duration)
        sessionTimer?.invalidate()
        sessionStartTime = nil
        
        DispatchQueue.main.async {
            self.currentSessionDuration = 0
        }
    }
    
    private func updateSessionDuration() {
        guard let startTime = sessionStartTime else { return }
        DispatchQueue.main.async {
            self.currentSessionDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    // MARK: - Feature Tracking
    
    func trackFeatureUsage(_ featureName: String) {
        let today = Calendar.current.startOfDay(for: Date())
        
        var analytics = loadDailyAnalytics(for: today) ?? createEmptyAnalytics(for: today)
        analytics.featureUsage[featureName, default: 0] += 1
        
        saveDailyAnalytics(analytics)
    }
    
    func trackScreenView(_ screenName: String) {
        trackFeatureUsage("Screen: \(screenName)")
    }
    
    func trackButtonTap(_ buttonName: String) {
        trackFeatureUsage("Button: \(buttonName)")
    }
    
    func trackEvent(_ eventName: String, parameters: [String: String]? = nil) {
        var fullEventName = "Event: \(eventName)"
        if let params = parameters, !params.isEmpty {
            let paramString = params.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            fullEventName += " [\(paramString)]"
        }
        trackFeatureUsage(fullEventName)
    }
    
    // MARK: - Private: Session Logging
    
    private func logSessionStart() {
        let today = Calendar.current.startOfDay(for: Date())
        
        var analytics = loadDailyAnalytics(for: today) ?? createEmptyAnalytics(for: today)
        
        // ✅ FIXED: Check if this user was already counted today
        let wasAlreadyCountedToday = analytics.uniqueUsers.contains(userId ?? "")
        
        // Always increment app launches (this is per open)
        analytics.totalAppLaunches += 1
        
        // Only add to unique users if NOT already counted today
        if let userId = userId, !wasAlreadyCountedToday {
            analytics.uniqueUsers.insert(userId)
            print("✅ Added user \(userId) to DAU (new today)")
        } else if let userId = userId {
            print("ℹ️ User \(userId) already counted today - not incrementing DAU")
        }
        
        saveDailyAnalytics(analytics)
        
        // ✅ NEW: Save today's date so we know they opened the app
        let dateFormatter = ISO8601DateFormatter()
        userDefaults.set(dateFormatter.string(from: today), forKey: lastSessionDateKey)
    }
    
    private func saveSession(_ session: UserSession, duration: TimeInterval) {
        let today = Calendar.current.startOfDay(for: Date())
        
        var analytics = loadDailyAnalytics(for: today) ?? createEmptyAnalytics(for: today)
        
        analytics.totalSessions += 1
        let newAverage = (analytics.averageSessionDuration * Double(analytics.totalSessions - 1) + duration) / Double(analytics.totalSessions)
        analytics.averageSessionDuration = newAverage
        
        saveDailyAnalytics(analytics)
        
        Task {
            await saveSessionToCloud(session, duration: duration)
        }
    }
    
    // MARK: - Local Storage
    
    private func createEmptyAnalytics(for date: Date) -> DailyAnalytics {
        return DailyAnalytics(date: date)
    }
    
    private func loadDailyAnalytics(for date: Date) -> DailyAnalytics? {
        let key = dailyAnalyticsKey + ISO8601DateFormatter().string(from: date)
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DailyAnalytics.self, from: data)
    }
    
    private func saveDailyAnalytics(_ analytics: DailyAnalytics) {
        let key = dailyAnalyticsKey + ISO8601DateFormatter().string(from: analytics.date)
        if let data = try? JSONEncoder().encode(analytics) {
            userDefaults.set(data, forKey: key)
            
            DispatchQueue.main.async {
                self.dailyAnalytics = analytics
            }
        }
    }
    
    func loadAnalytics() {
        let today = Calendar.current.startOfDay(for: Date())
        if let analytics = loadDailyAnalytics(for: today) {
            DispatchQueue.main.async {
                self.dailyAnalytics = analytics
            }
        }
        
        calculateWeeklyUsers()
        calculateMonthlyUsers()
    }
    
    // MARK: - Public: Analytics Retrieval
    
    func getDailyActiveUsers(for date: Date) -> Int {
        let analytics = loadDailyAnalytics(for: date)
        return analytics?.uniqueUsers.count ?? 0
    }
    
    func getWeeklyActiveUsers() -> Int {
        var users = Set<String>()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today),
               let analytics = loadDailyAnalytics(for: date) {
                users.formUnion(analytics.uniqueUsers)
            }
        }
        
        return users.count
    }
    
    func getMonthlyActiveUsers() -> Int {
        var users = Set<String>()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today),
               let analytics = loadDailyAnalytics(for: date) {
                users.formUnion(analytics.uniqueUsers)
            }
        }
        
        return users.count
    }
    
    func getWeeklyStats() -> [DailyAnalytics] {
        var stats: [DailyAnalytics] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today),
               let analytics = loadDailyAnalytics(for: date) {
                stats.append(analytics)
            }
        }
        
        return stats.sorted { $0.date < $1.date }
    }
    
    func getMonthlyStats() -> [DailyAnalytics] {
        var stats: [DailyAnalytics] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today),
               let analytics = loadDailyAnalytics(for: date) {
                stats.append(analytics)
            }
        }
        
        return stats.sorted { $0.date < $1.date }
    }
    
    func getTopFeatures(for date: Date? = nil, limit: Int = 5) -> [(String, Int)] {
        let targetDate = date ?? Calendar.current.startOfDay(for: Date())
        guard let analytics = loadDailyAnalytics(for: targetDate) else { return [] }
        
        return analytics.featureUsage
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }
    
    func getCurrentAnalyticsSnapshot() -> AnalyticsSnapshot {
        let today = Calendar.current.startOfDay(for: Date())
        let analytics = loadDailyAnalytics(for: today) ?? createEmptyAnalytics(for: today)
        
        let topFeatures = getTopFeatures(for: today)
            .reduce(into: [String: Int]()) { $0[$1.0] = $1.1 }
        
        return AnalyticsSnapshot(
            dau: analytics.uniqueUsers.count,
            wau: getWeeklyActiveUsers(),
            mau: getMonthlyActiveUsers(),
            totalSessions: analytics.totalSessions,
            averageSessionDuration: analytics.averageSessionDuration,
            topFeatures: topFeatures,
            timestamp: Date()
        )
    }
    
    // MARK: - Private: Helper Methods
    
    private func calculateWeeklyUsers() {
        DispatchQueue.main.async {
            self.weeklyDAU = self.getWeeklyActiveUsers()
        }
    }
    
    private func calculateMonthlyUsers() {
        DispatchQueue.main.async {
            self.monthlyDAU = self.getMonthlyActiveUsers()
        }
    }
    
    // MARK: - Cloud Sync
    
    private func saveSessionToCloud(_ session: UserSession, duration: TimeInterval) async {
        guard let userId = userId else { return }
        
        do {
            let sessionData: [String: Any] = [
                "sessionId": session.sessionId.uuidString,
                "userId": userId,
                "date": Timestamp(date: session.date),
                "timestamp": Timestamp(date: session.timestamp),
                "duration": duration,
                "appVersion": session.appVersion,
                "osVersion": session.osVersion,
                "deviceModel": session.deviceModel
            ]
            
            let dateString = ISO8601DateFormatter().string(from: session.date)
            try await firestore
                .collection("analytics")
                .document("sessions")
                .collection(dateString)
                .document(session.sessionId.uuidString)
                .setData(sessionData)
        } catch {
            print("❌ Failed to save session to cloud: \(error)")
        }
    }
    
    func syncAnalyticsToCloud() async {
        guard let userId = userId else { return }
        
        do {
            let today = Calendar.current.startOfDay(for: Date())
            guard let analytics = loadDailyAnalytics(for: today) else { return }
            
            let analyticsData: [String: Any] = [
                "date": Timestamp(date: analytics.date),
                "uniqueUsers": Array(analytics.uniqueUsers),
                "totalSessions": analytics.totalSessions,
                "totalAppLaunches": analytics.totalAppLaunches,
                "averageSessionDuration": analytics.averageSessionDuration,
                "featureUsage": analytics.featureUsage,
                "syncedAt": FieldValue.serverTimestamp()
            ]
            
            let dateString = ISO8601DateFormatter().string(from: analytics.date)
            try await firestore
                .collection("users")
                .document(userId)
                .collection("analytics")
                .document(dateString)
                .setData(analyticsData, merge: true)
        } catch {
            print("❌ Failed to sync analytics to cloud: \(error)")
        }
    }
    
    // MARK: - Data Export
    
    func exportAnalyticsAsJSON() -> String? {
        let snapshot = getCurrentAnalyticsSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(snapshot),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
    
    // MARK: - Data Reset (Testing & Debugging)
    
    /// Deletes all analytics data from UserDefaults
    func resetAllAnalytics() {
        let userDefaults = UserDefaults.standard
        
        // Get all keys that start with our analytics prefix
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let analyticsKeys = allKeys.filter { key in
            key.hasPrefix("DailyAnalytics_") || key == lastSessionDateKey
        }
        
        // Delete each key
        for key in analyticsKeys {
            userDefaults.removeObject(forKey: key)
        }
        
        print("✅ All analytics data deleted")
        
        // Reset published values
        DispatchQueue.main.async {
            self.dailyAnalytics = nil
            self.weeklyDAU = 0
            self.monthlyDAU = 0
        }
    }
    
    /// Deletes analytics for a specific date
    func resetAnalyticsForDate(_ date: Date) {
        let key = dailyAnalyticsKey + ISO8601DateFormatter().string(from: date)
        UserDefaults.standard.removeObject(forKey: key)
        
        let dateString = ISO8601DateFormatter().string(from: date)
        print("✅ Analytics for \(dateString) deleted")
        
        // Reload if it was today
        let today = Calendar.current.startOfDay(for: Date())
        if Calendar.current.isDate(date, inSameDayAs: today) {
            loadAnalytics()
        }
    }
    
    /// Deletes analytics for the last N days
    func resetAnalyticsForLastNDays(_ days: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let key = dailyAnalyticsKey + ISO8601DateFormatter().string(from: date)
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        print("✅ Analytics for last \(days) days deleted")
        loadAnalytics()
    }
    
    /// Deletes today's analytics only
    func resetTodayAnalytics() {
        let today = Calendar.current.startOfDay(for: Date())
        resetAnalyticsForDate(today)
    }
}

// MARK: - UIDevice Extension

extension UIDevice {
    static var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let scalar = element.value as? Int8, scalar != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(scalar)))
        }
        return identifier
    }
}
