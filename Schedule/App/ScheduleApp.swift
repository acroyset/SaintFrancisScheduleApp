//
//  ScheduleApp.swift
//  Schedule
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
import FirebasePerformance
import GoogleSignIn

enum AppRuntime {
    static let isUITesting: Bool = {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
#else
        false
#endif
    }()

    static let simulatesActiveScheduleRetry: Bool = {
#if DEBUG
        isUITesting
            && ProcessInfo.processInfo.arguments.contains("-ui-testing-active-schedule-retry")
#else
        false
#endif
    }()

    static let simulatesScheduleRefreshFailure: Bool = {
#if DEBUG
        isUITesting
            && ProcessInfo.processInfo.arguments.contains("-ui-testing-schedule-refresh-failure")
#else
        false
#endif
    }()

    static let usesGraphiteThemeFixture: Bool = {
#if DEBUG
        isUITesting
            && ProcessInfo.processInfo.arguments.contains("-ui-testing-graphite-theme")
#else
        false
#endif
    }()
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

@MainActor
private final class AppStartupController: ObservableObject {
    @Published private(set) var isReady: Bool

    private var hasStarted = false

    init() {
        isReady = AppRuntime.isUITesting
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard !AppRuntime.isUITesting else {
            isReady = true
            return
        }

        // Let SwiftUI commit the first production frame before starting SDK work.
        // This keeps launch responsive while still initializing every production
        // service before AuthenticationView can access Firebase Auth.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.configureProductionServices()
        }
    }

    private func configureProductionServices() {
        FirebaseConfiguration.shared.setLoggerLevel(.min)
        FirebaseApp.configure()

        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        Analytics.setAnalyticsCollectionEnabled(true)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        Performance.sharedInstance().isDataCollectionEnabled = true
        isReady = true
    }
}

private struct AppStartupView: View {
    @StateObject private var controller = AppStartupController()

    var body: some View {
        Group {
            if controller.isReady {
                AuthenticationView()
            } else {
                ZStack {
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()

                    ProgressView()
                        .tint(.blue)
                        .accessibilityLabel("Loading Schedule")
                        .accessibilityIdentifier("app.startup-status")
                }
            }
        }
        .onAppear(perform: controller.start)
    }
}

@main
struct ScheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    let notificationDelegate = NotificationDelegate()
    
    init() {
        if !AppRuntime.isUITesting {
            UNUserNotificationCenter.current().delegate = notificationDelegate
            ScheduleBackgroundManager.shared.registerBackgroundTasks()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            AppStartupView()
        }
    }
}
