# YourDay

You can download the app here: [link]  
The instructions below are for users with access to the source repository.

---

YourDay is a productivity iOS app designed to help users stay organized, receive smart reminders, and track their progress—all through a clean interface with thoughtful features such as onboarding tutorials and animated task completions.

## Features

- Create, edit, and manage to-do tasks
- Daily reminders (morning and night)
- Optional location-based reminders
- Guilt-based motivational notifications
- Gamified daily summary with progress rewards
- Task completion animation using sparkles
- Step-by-step onboarding tutorials

---

## How to Use the App (for Developers)

If you have access to this repository and would like to run the app locally, follow these steps:

### 1. Requirements

- Xcode 15 or later
- iOS 17+ (simulator or physical device)
- Swift and SwiftData
- Lottie (for animations)
- Firebase (for user authentication and optional cloud sync)

### 2. Setup Instructions

#### Clone the Repository

```bash
git clone https://github.com/rv-us/YourDay.git
cd yourday
```

#### Install Dependencies

1. Open `YourDay.xcodeproj` in Xcode.
2. Navigate to **File > Add Packages…**
3. Add the following dependencies using Swift Package Manager:
   - [Lottie](https://github.com/airbnb/lottie-ios)
   - Firebase (if login and sync features are used)

### 3. Running the App

1. Ensure your device or simulator is running iOS 17 or later.
2. Press `Cmd + R` in Xcode to run the app.
3. On first launch:
   - You will be guided by a short tutorial for task management.
   - Tap the "+" icon to add a new task.
   - Navigate to **Settings & Account** to configure notification times.
   - Enable extra reminders as needed.

---

## Developer Notes

- Onboarding tutorial state is managed via `@AppStorage`.
- Lottie animations are embedded using a `UIViewRepresentable` wrapper for SwiftUI.
- Local and push notifications are handled in `TodoViewModel`.
  
---

## Project Structure

```
YourDay/
├── Views/
│   ├── Todoview.swift
│   ├── NotificationSettingsView.swift
│   ├── LastDayView.swift
│   └── ...
├── ViewModels/
│   └── TodoViewModel.swift
│   └── ...
├── Assets/
│   └── splash_screen.json
├── YourDayApp.swift
```

---


