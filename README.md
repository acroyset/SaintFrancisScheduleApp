# Saint Francis Schedule

A comprehensive iOS schedule management app built specifically for Saint Francis High School students, featuring real-time class tracking, custom events, GPA calculation, and course planning tools.

## Overview

Saint Francis Schedule is a native SwiftUI application that provides students with:
- **Real-time schedule tracking** with live progress bars and countdowns
- **Custom personal events** with conflict detection
- **Course planning tools** including a full course catalog browser
- **GPA calculator** with weighted and unweighted calculations
- **Home screen widgets** for quick schedule access
- **Cloud sync** via Firebase for multi-device support
- **Daily notifications** for upcoming schedule types
- **News feed** integration for school announcements

## Features

### 📅 Schedule Management
- Automatic schedule fetching from Google Sheets
- Support for all Saint Francis day types (Gold 1/2, Brown 1/2, Activity, Liturgy, Special)
- Second lunch period configuration
- Passing period detection and tracking
- Real-time progress bars showing class completion
- Automatic timezone and date handling

### 📝 Custom Events
- Create personal events that integrate with your class schedule
- Repeat patterns: daily, weekly, biweekly, monthly, or one-time
- Automatic conflict detection with classes and other events
- Color-coded event organization
- Location and note fields for event details

### 🎓 Academic Tools
- **GPA Calculator**: Calculate weighted and unweighted GPA with Honors/AP support
- **Course Scheduler**: Browse 200+ Saint Francis courses with prerequisites and pathways
- **Final Grade Calculator**: Determine required exam scores to achieve target grades
- **Class Editor**: Customize class names, teachers, and room numbers

### 📱 Widgets
- **Small Widget**: Current/next class with progress bar
- **Medium Widget**: Current and next class overview
- **Large Widget**: Extended schedule view
- **Day Type Widget**: Shows today's schedule type and start time

### 🔔 Notifications
- Nightly notifications for tomorrow's schedule type
- Customizable notification time
- Background refresh for up-to-date schedule data

### ☁️ Cloud Features
- Firebase Authentication (Email/Password and Google Sign-In)
- Automatic cloud sync for classes and theme preferences
- Multi-device support
- Privacy-focused data storage

## Requirements

- **iOS**: 18.5 or later
- **Devices**: iPhone and iPad (universal)
- **Internet**: Required for initial schedule fetch and cloud sync

## Installation

This repository is for demonstration purposes only. The app is available on the App Store.

**Note**: This app is designed specifically for Saint Francis High School and requires the school's schedule data to function properly.

## Architecture

### Tech Stack
- **SwiftUI**: Modern declarative UI framework
- **WidgetKit**: Home screen widgets with live updates
- **Firebase**: Authentication and Firestore database
- **UserNotifications**: Local notification system
- **BackgroundTasks**: Automatic schedule updates

### Project Structure
```
Schedule/
├── App/                          # App lifecycle and configuration
├── Core/                         # Shared models and utilities
│   ├── Extensions/              # Color, Date, Array extensions
│   ├── Models/                  # Data models (Time, Day, ClassItem, etc.)
│   ├── Utilities/               # Helper functions and constants
│   └── Views/                   # Reusable UI components
├── Features/                     # Feature modules
│   ├── Authentication/          # Sign in/up with Firebase
│   ├── BackgroundTaskManager/   # Schedule refresh tasks
│   ├── Classes/                 # Class editor, GPA calc, course browser
│   ├── Events/                  # Custom event management
│   ├── Home/                    # Main schedule view
│   ├── News/                    # School news feed
│   ├── Profile/                 # User account management
│   ├── Settings/                # App preferences
│   └── VersionUpdate/           # Update prompt system
├── Shared/                      # Shared UI components
└── Resources/                   # Static data files

ScheduleWidget/                   # Widget extension
├── Core/                        # Widget-specific utilities
├── Providers/                   # Timeline providers
└── Views/                       # Widget UI
```

### Data Flow
1. **Schedule Loading**: Google Sheets → CSV → Parsed Dictionary → Local Storage
2. **Class Rendering**: Schedule Data + Current Time → Schedule Lines → UI
3. **Cloud Sync**: Local Changes → Firebase Firestore ↔ Other Devices
4. **Widget Updates**: Shared UserDefaults → Widget Timeline → Home Screen

## Key Components

### Schedule Rendering
The app uses a sophisticated time-based rendering system:
- Parses class templates (`$1`, `$2`, etc.) with actual class data
- Applies second lunch overrides automatically
- Calculates real-time progress for current classes
- Detects and displays passing periods (≤10 minutes)
- Supports custom events integrated into the timeline

### Theme System
Fully customizable color scheme:
- Primary, Secondary, and Tertiary color selection
- Real-time preview in color picker
- Dark/Light mode toggle
- Cloud sync for consistent appearance across devices
- Widget integration for unified experience

### Course Catalog
Complete Saint Francis course database:
- 200+ courses across all departments
- Prerequisite tracking and validation
- Next course recommendations
- Subject, level, and grade filtering
- Honors/AP designation
- Full-year and semester course support

## Privacy & Data

- **Local Storage**: Classes, preferences, and events stored locally
- **Cloud Storage**: Optional cloud sync via Firebase (user opt-in)
- **No Tracking**: No analytics or third-party tracking
- **Data Control**: Users can delete their cloud data at any time

## Current Version

**Beta 1.13** (as of February 2026)

Recent updates:
- Better news feed rendering
- Course scheduler with full catalog
- Enhanced notifications system
- GPA calculator improvements
- Various bug fixes

## Development Status

**Actively Maintained** - Regular updates with new features and improvements.

## Technical Notes

### Firebase Configuration
The app requires `GoogleService-Info.plist` (excluded from repository) for Firebase services.

### Background Tasks
Registered background task identifier: `Xcode.ScheduleApp.nightlyUpdate`

### App Groups
Uses `group.Xcode.ScheduleApp` for widget data sharing.

### Supported Families
- System Small
- System Medium  
- System Large

## Known Limitations

- Schedule data hardcoded to Saint Francis High School
- Requires active internet for initial setup
- Google Sheets dependency for schedule updates
- iOS 18.5+ only (uses latest SwiftUI features)
