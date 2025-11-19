//
//  ConflictRowView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

struct ConflictRowView: View {
    let conflict: EventConflict
    
    var body: some View {
        HStack {
            Image(systemName: conflictIcon)
                .foregroundColor(conflictColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.conflictingScheduleLine.className)
                    .font(.headline)
                
                Text(conflict.conflictingScheduleLine.timeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !conflict.conflictingScheduleLine.teacher.isEmpty {
                    Text(conflict.conflictingScheduleLine.teacher)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(conflictSeverityText)
                .font(.caption)
                .padding(4)
                .background(conflictColor.opacity(0.2))
                .cornerRadius(4)
        }
    }
    
    private var conflictIcon: String {
        switch conflict.severity {
        case .minor: return "exclamationmark.circle"
        case .major: return "exclamationmark.triangle"
        case .complete: return "xmark.circle"
        }
    }
    
    private var conflictColor: Color {
        switch conflict.severity {
        case .minor: return .yellow
        case .major: return .orange
        case .complete: return .red
        }
    }
    
    private var conflictSeverityText: String {
        switch conflict.severity {
        case .minor: return "Minor"
        case .major: return "Major"
        case .complete: return "Complete"
        }
    }
}
