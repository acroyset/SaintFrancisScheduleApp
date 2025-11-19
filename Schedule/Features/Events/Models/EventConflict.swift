//
//  EventConflict.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation

struct EventConflict {
    let event: CustomEvent
    let conflictingScheduleLine: ScheduleLine
    let severity: ConflictSeverity
}

enum ConflictSeverity {
    case minor    // Partial overlap (< 15 minutes)
    case major    // Significant overlap (15+ minutes)
    case complete // Event completely overlaps class
}
