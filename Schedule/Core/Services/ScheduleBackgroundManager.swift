import BackgroundTasks
import Foundation

let nightlyTaskID = "Xcode.ScheduleApp.nightlyUpdate"

class ScheduleBackgroundManager {
    static let shared = ScheduleBackgroundManager()
    private let operationQueue = OperationQueue()
    
    private init() {}
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: nightlyTaskID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleNightlyTask(task: refreshTask)
        }
    }
    
    func scheduleNextNightlyRefresh() {
        // UI tests intentionally skip registration; submitting an unregistered
        // identifier raises NSInternalInconsistencyException instead of throwing.
        guard !AppRuntime.isUITesting else { return }

        let request = BGAppRefreshTaskRequest(identifier: nightlyTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1 * 60 * 60) // 1 hour
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("❌ Failed to schedule:", error)
        }
    }
    
    func handleNightlyTask(task: BGAppRefreshTask) {
        scheduleNextNightlyRefresh()
        
        let op = BlockOperation {
            // Load scheduleDict directly from shared storage — no ContentView needed
            guard let data = SharedGroup.defaults.data(forKey: "ScheduleDict"),
                  let scheduleDict = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                NotificationManager.shared.scheduleNightly(dayCode: "")
                return
            }
            
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let formatter = DateFormatter()
            formatter.timeZone = .current
            formatter.dateFormat = "MM-dd-yy"
            let key = formatter.string(from: tomorrow)
            
            let tomorrowCode = scheduleDict[key]?[0] ?? ""
            NotificationManager.shared.scheduleNightly(dayCode: tomorrowCode)
        }
        
        task.expirationHandler = { op.cancel() }
        op.completionBlock = { [weak op] in
            task.setTaskCompleted(success: op?.isCancelled == false)
        }
        operationQueue.addOperation(op)
    }
}
