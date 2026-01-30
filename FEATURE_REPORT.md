# YourDay - Comprehensive Feature Report

**Generated:** $(date)  
**Project:** YourDay iOS Application  
**Total Files Analyzed:** 50+ Swift files

---

## Table of Contents

1. [App Architecture & Configuration](#app-architecture--configuration)
2. [Authentication & User Management](#authentication--user-management)
3. [Task Management System](#task-management-system)
4. [Notes Management](#notes-management)
5. [Garden Gamification System](#garden-gamification-system)
6. [Social Features](#social-features)
7. [Notification System](#notification-system)
8. [Data Persistence & Sync](#data-persistence--sync)
9. [UI/UX Features](#uiux-features)
10. [Tutorial System](#tutorial-system)

---

## App Architecture & Configuration

### YourDayApp.swift
- **Main App Entry Point**
  - Firebase initialization and configuration
  - SwiftData model container setup (TodoItem, NoteItem, PlayerStats, DailySummaryTask)
  - Tab bar appearance customization
  - Crash prevention system for corrupted UserDefaults data
  - App restart view with date-based refresh logic
  - Location manager initialization

### Configuration Files
- **Info.plist**
  - URL schemes for Google Sign-In
  - Custom URL scheme for app deep linking
  
- **YourDay.entitlements**
  - App sandbox configuration
  - Location services permissions
  - User-selected file read access

---

## Authentication & User Management

### LoginView.swift
- **Multiple Authentication Methods**
  - Email/password sign-in and registration
  - Guest mode with display name
  - Google Sign-In (UI commented out but backend ready)
  - Apple Sign-In (UI commented out but backend ready)
  - Password reset functionality
  
- **User Experience**
  - Segmented picker for login vs. registration
  - Form validation
  - Loading states
  - Error message display
  - Keyboard dismissal on background tap
  - Focus state management

### LoginViewModel.swift
- **Authentication State Management**
  - Firebase Auth state listener
  - Network availability monitoring
  - Guest session management
  - User profile management (display name updates)
  
- **Data Synchronization**
  - PlayerStats sync to Firestore
  - Leaderboard entry updates
  - Fresh login detection and data loading
  - Local SwiftData integration
  
- **Account Management**
  - Sign out with data sync
  - Account deletion with Firestore cleanup
  - Display name uniqueness validation
  - Network-aware operations

---

## Task Management System

### TodoItem.swift (Data Model)
- **Task Properties**
  - Title, detail, due date
  - Completion status with timestamp
  - Subtasks array
  - Task origin (Today vs. Master List)
  - Position for sorting
  - Shared task linking (sharedTaskId, isSharedPending)

### Todoview.swift
- **Main Task Interface**
  - Segmented filter (Today/Master List)
  - In Progress and Completed sections
  - Drag-and-drop reordering
  - Swipe-to-delete
  - Add task button
  - Daily summary access (star icon)
  - Tutorial overlay system
  
- **Task Organization**
  - Position-based sorting
  - Filter by origin
  - Visual separation of active vs. completed

### NewItemview.swift
- **Task Creation/Editing**
  - Title and description fields
  - Due date picker (graphical calendar)
  - Subtask management (add/remove)
  - Origin selection (Today/Master List)
  - AI task generation using Gemini 2.5 Flash
  - Task editing for existing items
  
- **AI Features**
  - Natural language task description
  - Automatic task parsing (title, description, due date, subtasks)
  - Integration with Firebase Vertex AI

### TodoListItemView.swift
- **Task Display Component**
  - Checkbox toggle with animation
  - Title and description display
  - Subtask list rendering
  - Edit on tap
  - Shared task status indicators
  - Real-time sync with Firestore for shared tasks

### SubtaskCheckboxView.swift
- **Subtask Component**
  - Individual checkbox
  - Completion timestamp tracking
  - Visual feedback on completion

### MigrateTasksView.swift
- **Task Migration System**
  - Review incomplete tasks from previous days
  - Select tasks to move to today
  - Discard completed tasks
  - Preserve subtask status during migration

### PointManager.swift
- **Points & XP System**
  - Daily point evaluation (runs at midnight)
  - Garden value-based point calculation
  - Subtask point distribution
  - XP tracking and level progression
  - Daily summary generation
  - Prevents duplicate evaluation

### LastDayView.swift
- **Daily Summary Display**
  - Animated point display
  - XP progress visualization
  - Level-up animations
  - Task breakdown by points earned
  - Completion percentage pie chart
  - Historical date navigation
  - Task origin indicators (Today/Master List)

---

## Notes Management

### NoteItem.swift (Data Model)
- **Note Properties**
  - Unique UUID identifier
  - Content (text)
  - Creation timestamp

### AddNotesView.swift
- **Notes Interface**
  - List of all notes (sorted by date)
  - Create new notes
  - Edit/delete notes
  - Multi-select mode
  - AI task generation from notes (Gemini 2.5 Flash)
  - Origin selection for generated tasks (Today/Master List)
  - Tutorial overlay system

### NewNoteView.swift
- **Note Creation**
  - Text editor
  - Save/cancel actions
  - Validation (non-empty content)

### NoteDetailView.swift
- **Note Editing**
  - Full-screen text editor
  - Save changes
  - Auto-save on dismiss

---

## Garden Gamification System

### PlayerStats.swift (Data Model)
- **Player Progression**
  - Total points (currency)
  - Player level and XP
  - Garden value calculation
  - Plot ownership (expandable with level)
  - Fertilizer count
  - Plant inventory (unplaced)
  - Placed plants array
  
- **Plant System**
  - Rarity levels (Common, Uncommon, Rare, Epic, Legendary)
  - Theme system (Spring, Summer, Fall, Winter)
  - Growth mechanics (days to grow, watering)
  - Seasonal bonus multipliers (1.5x for matching season)
  - Plant selling (1.5x base value)
  - Fertilizer conversion (10 plants = 1 fertilizer)
  
- **Shop & Gacha**
  - Theme-based plant pulls
  - 2-plant pull (100 points)
  - 10-plant pull (500 points, guaranteed Rare+)
  - Rarity probability system
  - Inventory management

### Gardenview.swift
- **Main Garden Interface**
  - Grid-based plot system
  - Plant placement and management
  - Water all plants button
  - Sell mode (tap to sell grown plants)
  - Fertilizer mode (instant growth)
  - Plot purchase system
  - Inventory access
  - Shop access
  - Leaderboard access
  - Plant drag-and-drop reordering
  - Plant info view
  - Lottie watering animation
  - Visual feedback system (points earned, notifications)
  - Tutorial overlay system
  
- **Plant Management**
  - Tap empty plot to plant
  - Long-press for context menu (water/sell)
  - Visual indicators for growth status
  - Seasonal theme display
  - Garden value display

### Shopview.swift
- **Gacha Shop Interface**
  - Theme selection (Spring, Summer, Fall, Winter)
  - Theme banners with seasonal imagery
  - Pull animations (shuffle, reveal)
  - Skip animation option
  - Pull results display
  - Cost display and validation
  - Guaranteed rare indicator for 10-pulls

### InventoryView.swift
- **Plant Inventory**
  - View all unplaced plants
  - Sort by default, theme, or rarity
  - Quantity display
  - Plant selection for planting
  - Fertilizer conversion interface
  - Grouped display by theme/rarity

### PlantInfoView.swift
- **Plant Details**
  - Plant name and visual
  - Status (growing/fully grown)
  - Rarity and theme display
  - Current value calculation
  - Seasonal bonus indicator
  - Plant description

### PlantLibrary.swift
- **Plant Database**
  - 25+ plant blueprints
  - Organized by rarity and theme
  - Asset management
  - Visual display components
  - Plant lookup functions

### PlayerStatsCodeable.swift
- **Firestore Sync Model**
  - Codable conversion for PlayerStats
  - Schema versioning for migrations
  - Bidirectional conversion (Model ↔ Codable)
  - Garden value calculation

---

## Social Features

### SocialView.swift
- **Social Hub**
  - Friends management access
  - Chat list navigation
  - Placeholder for future features

### FriendsView.swift
- **Friend Management**
  - User search by display name
  - Send friend requests
  - Accept/decline pending requests
  - View accepted friends
  - Remove friends
  - Real-time friend request listener
  - Live friend list updates

### ChatListView.swift
- **Chat List**
  - List of all friends with chat access
  - Last message preview
  - Timestamp formatting (today, yesterday, week, date)
  - Unread message indicators
  - Last seen status
  - Navigation to individual chats

### ChatDetailView.swift
- **Individual Chat**
  - Real-time message display
  - Message sending
  - Shared task composer
  - Progress sharing picker
  - Shared tasks inbox
  - Auto-scroll to latest message
  - Message timestamp display

### ChatMessage.swift (Data Model)
- **Message Properties**
  - Sender/receiver IDs
  - Content
  - Timestamp
  - Firestore document ID

### SharedTask.swift (Data Model)
- **Shared Task Properties**
  - Sender/receiver IDs
  - Title, detail, due date
  - Acceptance status
  - Completion status
  - Subtasks array
  - Creation and completion timestamps

### SharedTasksInboxView.swift
- **Shared Tasks Management**
  - View all shared tasks with a friend
  - Accept/reject pending tasks
  - Nudge functionality
  - Delete shared tasks
  - Real-time updates
  - Subtask display and management

### SharedTaskDetailView.swift
- **Shared Task Details**
  - Full task information
  - Subtask toggle (syncs to Firestore)
  - Accept/reject actions
  - Nudge button
  - Real-time task updates

### ShareProgressPickerView.swift
- **Progress Sharing**
  - Select completed/in-progress tasks to share
  - Exclude already-shared tasks
  - Share with subtask status
  - Link local task to shared task
  - Track shared progress per friend

### LeaderBoardView.swift
- **Leaderboard Display**
  - Global leaderboard
  - Friends-only filter
  - Rank, name, level, garden value
  - Current user highlighting
  - Scroll to user's rank
  - Pull-to-refresh
  - Loading and error states

### LeaderBoardViewModel.swift
- **Leaderboard Logic**
  - Fetch entries from Firestore
  - Rank calculation
  - Current user rank tracking
  - Friends-only filtering
  - Refresh functionality

### LeaderBoardEntry.swift (Data Model)
- **Entry Properties**
  - User ID
  - Display name
  - Player level
  - Garden value
  - Rank (calculated)

---

## Notification System

### NotificationSettingsView.swift
- **Notification Configuration**
  - Enable/disable scheduled notifications
  - Enable/disable location-based reminders
  - Morning reminder time picker
  - Night reminder time picker
  - Extra reminders slider (0-10)
  - Save and schedule functionality
  - Account information display
  - Display name editing
  - Sign out/exit guest mode
  - Account deletion
  - Tutorial overlay system

### NotificationManager.swift
- **Smart Notification Generation**
  - Task-based notification content
  - Morning messages (motivational, task-focused)
  - Night messages (progress summary)
  - Extra reminder messages (context-aware)
  - Progress percentage calculations
  - Task count awareness
  - Dynamic message generation based on task state

### TodoViewModel.swift
- **Notification Scheduling**
  - Daily reminder scheduling
  - Morning and night reminders
  - Extra reminder distribution
  - Task-aware content generation
  - Reschedule on task changes

### LocationManager.swift
- **Location-Based Reminders**
  - CoreLocation integration
  - Permission handling
  - Location updates
  - Gemini AI integration for context-aware reminders
  - Idle time detection
  - Daily reminder limit tracking
  - Smart notification evaluation

---

## Data Persistence & Sync

### FirebaseManager.swift
- **Firebase Operations**
  - PlayerStats save/load
  - Leaderboard entry management
  - User search functionality
  - Friend request system
  - Friend management
  - Chat message sending/listening
  - Shared task operations
  - Display name validation
  - Account data deletion
  - Real-time listeners management

### SwiftData Models
- **Local Storage**
  - TodoItem (tasks)
  - NoteItem (notes)
  - PlayerStats (game progress)
  - DailySummaryTask (historical summaries)
  - Automatic persistence
  - Query support

### Data Sync Strategy
- **Hybrid Approach**
  - Local-first with SwiftData
  - Cloud sync with Firestore
  - Conflict resolution
  - Offline support
  - Fresh login detection
  - Incremental updates

---

## UI/UX Features

### Theme System
- **Dynamic Colors**
  - Light theme (primary colors)
  - Consistent color palette across app
  - Themed components (garden, shop, etc.)
  - Accessibility considerations

### SplashScreenView.swift
- **App Launch**
  - Lottie animation
  - Smooth transition to main app
  - Animation completion handling

### LottieView.swift
- **Animation Support**
  - Lottie animation wrapper
  - Play/pause control
  - Loop mode configuration
  - Animation speed control
  - Used for splash screen and watering animations

### ContentView.swift
- **Main App Coordinator**
  - Tab view navigation
  - Authentication state management
  - New day logic processing
  - Task migration prompts
  - Plant withering system (after 5 days)
  - Daily summary triggers
  - Data cleanup on logout

### ConfirmGeneratedTasksView.swift
- **AI Task Confirmation**
  - Review generated tasks
  - Select tasks to add
  - Visual selection indicators

---

## Tutorial System

### TutorialOverlay.swift
- **Garden Tutorial**
  - Welcome screen
  - Shop explanation
  - Planting guide
  - Watering instructions
  - Fertilizer usage
  - Selling plants
  - Plot expansion
  - Interactive step progression
  - Skip functionality

### TodoTutorialOverlay.swift
- **Task Tutorial**
  - Welcome message
  - Filter explanation
  - Add task guide
  - Summary access
  - Migration explanation
  - Highlight system for UI elements
  - User action requirements

### NotesTutorialOverlay.swift
- **Notes Tutorial**
  - Welcome to notes
  - Create note guide
  - Select note instructions
  - Generate tasks explanation
  - Completion message

### NotificationsTutorialOverlay.swift
- **Notifications Tutorial**
  - Welcome to notifications
  - Scheduled notifications toggle
  - Location reminders toggle
  - Time setting guide
  - Extra reminders slider
  - Completion message

---

## Key Features Summary

### Core Productivity Features
✅ Task management with subtasks  
✅ Today vs. Master List organization  
✅ Notes with AI task generation  
✅ Daily summaries with points/XP  
✅ Task migration between lists  
✅ Drag-and-drop task reordering  

### Gamification Features
✅ Garden system with plant collection  
✅ Gacha shop with theme-based pulls  
✅ Plant rarity system (5 tiers)  
✅ Seasonal bonuses  
✅ Level progression with XP  
✅ Plot expansion system  
✅ Fertilizer system  
✅ Plant selling for points  

### Social Features
✅ Friend system with requests  
✅ Real-time chat messaging  
✅ Shared task collaboration  
✅ Progress sharing  
✅ Global and friends-only leaderboards  
✅ Last seen status  

### Smart Features
✅ AI task generation (Gemini 2.5 Flash)  
✅ AI note-to-task conversion  
✅ Location-based smart reminders  
✅ Task-aware notifications  
✅ Context-aware messaging  

### Technical Features
✅ Firebase authentication (Email, Google, Apple ready)  
✅ Guest mode support  
✅ Offline-first with cloud sync  
✅ Real-time data synchronization  
✅ Crash prevention system  
✅ Network availability monitoring  
✅ Schema versioning for migrations  

---

## File Count Summary

- **View Files:** 30
- **ViewModel Files:** 18
- **Configuration Files:** 3
- **Total Swift Files:** 50+

---

## Technology Stack

- **Framework:** SwiftUI
- **Backend:** Firebase (Auth, Firestore)
- **Local Storage:** SwiftData
- **AI:** Google Gemini 2.5 Flash (Vertex AI)
- **Animations:** Lottie
- **Location:** CoreLocation
- **Notifications:** UserNotifications

---

## Notable Implementation Details

1. **Hybrid Data Strategy:** Local-first with SwiftData, cloud sync with Firestore
2. **Real-time Updates:** Extensive use of Firestore listeners for chat, shared tasks, friends
3. **AI Integration:** Gemini 2.5 Flash for task generation and smart reminders
4. **Gamification Depth:** Complex plant system with rarity, themes, seasonal bonuses
5. **Tutorial System:** Comprehensive onboarding for all major features
6. **Offline Support:** Guest mode and local data persistence
7. **Social Collaboration:** Real-time shared tasks with subtask synchronization
8. **Smart Notifications:** Context-aware, task-based notification content

---

*Report generated by comprehensive codebase analysis*
