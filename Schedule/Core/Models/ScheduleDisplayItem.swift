
import Foundation

enum ScheduleDisplayItem {
    case scheduleLine(ScheduleLine)
    case customEvent(CustomEvent)
    
    var startTimeSeconds: Int {
        switch self {
        case .scheduleLine(let line):
            return line.startSec ?? Int.max
        case .customEvent(let event):
            return event.startTime.seconds
        }
    }
}
