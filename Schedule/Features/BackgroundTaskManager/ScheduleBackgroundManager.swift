import BackgroundTasks
import Foundation

let nightlyTaskID = "Xcode.ScheduleApp.nightlyUpdate"

class ScheduleBackgroundManager {
    static let shared = ScheduleBackgroundManager()
    
    private init() {}
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: nightlyTaskID,
            using: nil
        ) { task in
            self.handleNightlyTask(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleNextNightlyRefresh() {
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
            let tomorrowCode = ContentView().getTomorrowsDayCode()
            NotificationManager.shared.scheduleNightly(dayCode: tomorrowCode)
        }
        
        task.expirationHandler = {
            op.cancel()
        }
        
        op.completionBlock = {
            task.setTaskCompleted(success: !op.isCancelled)
        }
        
        OperationQueue().addOperation(op)
    }
}
