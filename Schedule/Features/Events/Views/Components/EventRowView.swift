//
//  EventRowView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

struct EventRowView: View {
    let event: CustomEvent
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: event.color))
                .frame(width: 8, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(PrimaryColor)
                
                Text("\(event.startTime.string()) - \(event.endTime.string())")
                    .font(.subheadline)
                    .foregroundColor(PrimaryColor.opacity(0.7))
                
                if !event.location.isEmpty {
                    HStack {
                        Image(systemName: "location")
                            .font(.caption)
                        Text(event.location)
                            .font(.caption)
                    }
                    .foregroundColor(PrimaryColor.opacity(0.6))
                }
                
                if event.repeatPattern != .none {
                    HStack {
                        Image(systemName: "repeat")
                            .font(.caption)
                        Text(event.repeatPattern.description)
                            .font(.caption)
                    }
                    .foregroundColor(PrimaryColor.opacity(0.6))
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { event.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: event.color)))
                
                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(PrimaryColor.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(event.isEnabled ? 1.0 : 0.6)
    }
}
