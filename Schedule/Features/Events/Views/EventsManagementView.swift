//
//  EventsManagementView.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
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
                eventsManager: eventsManager,
                currentDayCode: "G1",
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
                eventsManager: eventsManager,
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
            case .none: return "One-time Events"
            case .daily: return "Daily Events"
            case .weekly: return "Weekly Events"
            case .biweekly: return "Biweekly Events"
            case .monthly: return "Monthly Events"
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
