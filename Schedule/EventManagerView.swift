//
//  EventManagerView.swift
//  Schedule
//

import SwiftUI

struct EventsManagementView: View {
    @StateObject private var eventsManager = CustomEventsManager()
    @State private var showingAddEvent = false
    @State private var editingEvent: CustomEvent?
    @State private var searchText = ""
    
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    
    var filteredEvents: [CustomEvent] {
        if searchText.isEmpty {
            return eventsManager.events
        } else {
            return eventsManager.events.filter { event in
                event.title.localizedCaseInsensitiveContains(searchText) ||
                event.location.localizedCaseInsensitiveContains(searchText) ||
                event.note.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if eventsManager.events.isEmpty {
                    emptyStateView
                } else {
                    eventsList
                }
            }
            .navigationTitle("My Events")
            .searchable(text: $searchText, prompt: "Search events")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddEvent = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventView(
                isPresented: $showingAddEvent,
                currentDayCode: "G1", // Default
                currentDate: Date(),
                scheduleLines: [],
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
        .sheet(item: $editingEvent) { event in
            AddEventView(
                isPresented: Binding(
                    get: { editingEvent != nil },
                    set: { if !$0 { editingEvent = nil } }
                ),
                editingEvent: event,
                currentDayCode: "G1",
                currentDate: Date(),
                scheduleLines: [],
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(PrimaryColor.opacity(0.6))
            
            Text("No Personal Events")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(PrimaryColor)
            
            Text("Add events like study sessions, meetings, or personal appointments to see them in your schedule.")
                .multilineTextAlignment(.center)
                .foregroundColor(PrimaryColor.opacity(0.7))
                .padding(.horizontal, 32)
            
            Button(action: {
                showingAddEvent = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Your First Event")
                }
                .font(.headline)
                .foregroundColor(TertiaryColor)
                .padding()
                .background(PrimaryColor)
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var eventsList: some View {
        List {
            ForEach(groupedEvents, id: \.key) { group in
                Section(header: Text(group.key).foregroundColor(PrimaryColor)) {
                    ForEach(group.value) { event in
                        EventRowView(
                            event: event,
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor,
                            onEdit: { editingEvent = event },
                            onToggle: { eventsManager.toggleEvent(event) },
                            onDelete: { eventsManager.deleteEvent(event) }
                        )
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private var groupedEvents: [(key: String, value: [CustomEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { event in
            switch event.repeatPattern {
            case .none:
                return "One-time Events"
            case .daily:
                return "Daily Events"
            case .weekly:
                return "Weekly Events"
            case .biweekly:
                return "Biweekly Events"
            case .monthly:
                return "Monthly Events"
            }
        }
        
        return grouped.sorted { first, second in
            let order = ["Daily Events", "Weekly Events", "Biweekly Events", "Monthly Events", "One-time Events"]
            let firstIndex = order.firstIndex(of: first.key) ?? order.count
            let secondIndex = order.firstIndex(of: second.key) ?? order.count
            return firstIndex < secondIndex
        }
    }
}

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
            // Event color indicator
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
            
            // Event status and menu
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

// MARK: - Integration into your main ContentView

// Add this as a new case in your Window enum:
// case .Events

// Add "Events" to your tools array:
// let tools = ["Home", "News", "Clubs", "Edit Classes", "Events", "Settings", "Profile"]

// Add this case to your window switch statement:
// case .Events:
//     EventsManagementView(
//         PrimaryColor: PrimaryColor,
//         SecondaryColor: SecondaryColor,
//         TertiaryColor: TertiaryColor
//     )
