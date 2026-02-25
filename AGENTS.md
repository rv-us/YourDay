# AGENTS.md

## Project Overview

**YourDay** is a native iOS productivity app built with Swift/SwiftUI. It uses SwiftData for local persistence, Firebase for authentication and cloud sync, and Lottie for animations. The project is a single Xcode project (`YourDay.xcodeproj`) — not a monorepo.

## Cursor Cloud specific instructions

### Platform Constraint

This is a **native iOS project** that requires **macOS with Xcode 15+** to build, run, and execute tests. The Cursor Cloud VM runs Linux, so building and running the app (via `xcodebuild` or the iOS Simulator) is **not possible** in this environment.

### What You CAN Do on Linux

- **Lint**: Run `swiftlint lint` from the repo root. SwiftLint (static binary) is installed at `/usr/local/bin/swiftlint`. It runs without a Swift toolchain.
- **Read/edit Swift source files**: All app source is under `YourDay/Views/` and `YourDay/ViewModels/`. Tests are in `YourDayTests/` and `YourDayUITests/`.
- **Review project config**: The Xcode project file is at `YourDay.xcodeproj/project.pbxproj`. SPM resolved dependencies are in `YourDay.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

### What You CANNOT Do on Linux

- Build the app (`xcodebuild` requires macOS + Xcode)
- Run the iOS Simulator
- Run unit tests (`YourDayTests`) or UI tests (`YourDayUITests`)
- Resolve/update SPM packages (requires Xcode or `swift package` with iOS SDK)

### Key Commands

| Action | Command | Notes |
|---|---|---|
| Lint all Swift files | `swiftlint lint` | Runs from repo root; exits non-zero if errors found |
| Lint with JSON output | `swiftlint lint --reporter json` | Useful for programmatic analysis |
| Lint specific file | `swiftlint lint --path YourDay/Views/Todoview.swift` | Lint a single file |

### Dependencies (SPM)

Dependencies are managed via Swift Package Manager through Xcode. Key packages:
- `firebase-ios-sdk` 11.12.0 — Auth, Firestore, VertexAI
- `GoogleSignIn-iOS` 8.0.0 — Google Sign-In
- Lottie — Animations (referenced in code; may need manual SPM addition in Xcode)

### Firebase Configuration

A `GoogleService-Info.plist` is committed with Firebase project `yourday-2998f`. Firebase is initialized on app launch via `FirebaseApp.configure()`.

### Notes

- The existing unit tests (`YourDayTests.swift`) and UI tests (`YourDayUITests.swift`, `YourDayUITestsLaunchTests.swift`) contain only Xcode boilerplate — no meaningful test coverage exists.
- Lottie and GoogleGenerativeAI are imported in source but may not be fully wired in the committed SPM configuration. If builds fail, check **File > Add Packages** in Xcode.
