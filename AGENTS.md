# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build and Run Commands

```bash
# Open project in Xcode
open YourDay.xcodeproj

# Build from command line
xcodebuild -project YourDay.xcodeproj -scheme YourDay -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project YourDay.xcodeproj -scheme YourDay -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Requirements: Xcode 15+, iOS 17+ target, Swift 5.9+

## Architecture Overview

YourDay is a gamified iOS productivity app using SwiftUI + SwiftData for local persistence and Firebase for cloud sync/auth.

### Data Flow Pattern
- **SwiftData Models** (`TodoItem`, `PlayerStats`, `NoteItem`, `DailySummaryTask`) are the source of truth for local data
- **Firebase/Firestore** syncs user data across devices via `FirebaseManager` (singleton)
- **Codable versions** (e.g., `PlayerStatsCodable`) bridge SwiftData models to Firestore serialization
- Authentication supports both Firebase Auth and guest mode via `LoginViewModel`

### Key Singletons
- `FirebaseManager.shared` - All Firestore operations (CRUD, listeners, friend requests, shared tasks)
- `GoogleCalendarManager.shared` - Google Calendar API integration (read/write events, OAuth scopes)
- `NotificationManager.shared` - Task-aware push notification generation

### Core ViewModels
- `LoginViewModel` - Auth state, session management, Firebase ↔ SwiftData sync
- `TodoViewModel` - Notification scheduling, daily reminder orchestration
- `SchedulingAssistantViewModel` - AI scheduling via Firebase Vertex AI (Gemini), calendar slot analysis
- `BacklogViewModel` - Task backlog management for smart scheduling

### Gamification System
- `PlayerStats` tracks points, XP, levels, garden (plants), and inventory
- `PointManager.evaluateDailyPoints()` calculates daily points based on task completion
- Garden mechanics: plants grow daily when watered, wither after 5+ days of inactivity
- Plants have rarity tiers (Common→Legendary) and seasonal themes affecting value

### Social Features
- Friend system via Firestore subcollections (`users/{uid}/friends`, `friend_requests`)
- `SharedTask` model enables task sharing between friends with progress sync
- Chat messaging stored in `chat_messages` collection

### Smart Scheduling (AI Integration)
- Uses Firebase Vertex AI with Gemini model for schedule proposals
- `SchedulingAssistantViewModel` builds context from: backlog items, calendar events, user preferences, decline history
- Learns user constraints (wake time, lunch, recurring commitments) from conversation
- Creates Google Calendar events on proposal acceptance

### Tutorial System
- Onboarding tutorials per feature stored in `@AppStorage` (e.g., `hasCompletedTodoTutorial`)
- Tutorial overlays: `TutorialOverlay`, `TodoTutorialOverlay`, `NotesTutorialOverlay`, etc.

## Key File Locations

- **App Entry**: `YourDayApp.swift` - Firebase config, crash prevention, app restart logic
- **Main Navigation**: `Views/ContentView.swift` - TabView with auth state handling
- **SwiftData Models**: `ViewModels/TodoItem.swift`, `ViewModels/PlayerStats.swift`, `ViewModels/NoteItem.swift`
- **Firebase Config**: `GoogleService-Info.plist`

## Important Patterns

### Date Handling
The app uses `yyyy-MM-dd` string format for date comparisons in `@AppStorage`. Invalid dates are cleared on app launch in `setupCrashPrevention()`.

### Task Migration
On new day detection, incomplete tasks prompt `MigrateTasksView` for user review.

### Calendar Integration
`GoogleCalendarManager` requires the `https://www.googleapis.com/auth/calendar` scope for write operations. Sign-in state is restored automatically on app launch.
