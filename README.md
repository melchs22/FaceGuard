# FaceGuard 👁️🔒

**FaceGuard** is a macOS menu bar security app that continuously monitors your webcam and automatically locks your screen if an unauthorized face is detected.

---

## Features

- 🟢 **Real-time face detection** via Apple's Vision framework
- 🔐 **Cosine similarity matching** with a rolling 5-frame average
- 🎥 **Live enrollment** with camera preview and progress guide
- ⏱ **No-face lock timer** (configurable 3–60 seconds)
- 👥 **Stranger cooldown** (must detect unauthorized face for 2+ seconds to lock)
- 📊 **Live match score** in the menu bar
- ⚙️ **Full preferences panel** — all settings user-configurable
- 📸 **Intruder snapshots** saved to ~/Library/Logs/FaceGuard/intruders/
- 🚨 **Panic shortcut** ⌘+Shift+L for immediate lock
- 🔁 **Launch at login** via SMAppService (macOS 13+)

---

## Requirements

| Requirement | Value |
|---|---|
| macOS | 13.0 Ventura or later |
| Xcode | 15.0 or later |
| Language | Swift 5.9+ |
| Hardware | Any Mac with a built-in or USB webcam |

---

## Step-by-Step Xcode Setup

### Step 1 — Create a New Xcode Project

1. Open **Xcode**
2. Choose **File → New → Project…**
3. Select **macOS → App**
4. Fill in:
   - **Product Name**: `FaceGuard`
   - **Bundle Identifier**: `com.yourname.FaceGuard`
   - **Language**: Swift
   - **Interface**: SwiftUI *(we override this with AppKit/AppDelegate)*
5. Uncheck: `Include Tests` (optional)
6. Choose a save location (e.g., your Desktop)

---

### Step 2 — Configure the Target

#### a) Deployment Target
- Select the **FaceGuard** target → **General** tab
- Set **Minimum Deployments** → **macOS 13.0**

#### b) Signing
- Under **Signing & Capabilities** → set your **Team**
- Xcode will auto-generate a provisioning profile

#### c) Entitlements
- Under **Signing & Capabilities** → click **+ Capability**
- Add: **Camera**
- Add: **Apple Events** *(needed for screen locking)*
- OR: Replace the auto-generated `.entitlements` file with `FaceGuard.entitlements` from this repo

---

### Step 3 — Configure Info.plist

Xcode 13+ uses an **Info** tab instead of a file. Add these keys:

| Key | Type | Value |
|---|---|---|
| `LSUIElement` | Boolean | YES |
| `NSCameraUsageDescription` | String | `FaceGuard uses your camera to detect who is looking at your screen…` |
| `NSAppleEventsUsageDescription` | String | `FaceGuard needs this to lock your screen.` |
| `LSMinimumSystemVersion` | String | `13.0` |

> **Alternative**: Replace the generated Info.plist with the one from `FaceGuard/Resources/Info.plist`.

---

### Step 4 — Delete Default Generated Files

Delete these Xcode-generated files (they conflict with our AppDelegate approach):
- `ContentView.swift`
- `FaceGuardApp.swift` *(if it has `@main`)*

> ⚠️ Make sure **no file** has `@main` or `@NSApplicationMain` except `AppDelegate.swift`.

---

### Step 5 — Add All Source Files

Add the following files to your Xcode project. Organize them into Groups:

```
FaceGuard/
├── App/
│   └── AppDelegate.swift
├── Camera/
│   ├── CameraManager.swift
│   └── FrameProcessor.swift
├── Face/
│   ├── FaceDetector.swift
│   ├── FaceEnroller.swift
│   └── FaceMatcher.swift
├── Security/
│   └── ScreenLocker.swift
├── UI/
│   ├── MenuBarController.swift
│   ├── EnrollmentWindowController.swift
│   ├── EnrollmentView.swift
│   ├── PreferencesWindowController.swift
│   ├── PreferencesView.swift
│   └── WarningOverlayWindow.swift
└── Utilities/
    ├── AppLogger.swift
    ├── EmbeddingStore.swift
    └── Settings.swift
```

---

### Step 6 — Link Frameworks

In the target's **General → Frameworks, Libraries, and Embedded Content**, verify:

| Framework | Why |
|---|---|
| `AVFoundation.framework` | Camera capture |
| `Vision.framework` | Face detection |
| `CoreImage.framework` | Frame processing |
| `ServiceManagement.framework` | Launch at login |

Xcode usually adds these automatically from `import` statements.

---

### Step 7 — Build Settings

Under **Build Settings**:

| Setting | Value |
|---|---|
| Swift Language Version | Swift 5 |
| macOS Deployment Target | 13.0 |
| Enable Hardened Runtime | YES |
| Code Signing Style | Automatic |

---

### Step 8 — Build & Run

1. Select the **FaceGuard** scheme
2. Press **⌘+R** to build and run
3. macOS will ask for camera permission — click **Allow**
4. The enrollment window opens automatically on first launch

---

## How to Use

### First Launch
1. The **Enrollment Window** opens automatically
2. Centre your face in the circular guide
3. Click **Start Enrollment** — hold still for 3 seconds
4. After 10 frames are captured, you'll see **"Face enrolled successfully"**
5. The window closes and FaceGuard begins protecting your screen

### Daily Use
The icon colour shows current status:
- 🟢 **Green eye** = Authorized, you're recognized
- 🔴 **Red lock** = Unauthorized face detected
- ⚪ **Gray eye/slash** = No face, countdown active
- 🟡 **Yellow eye** = Protection paused
- Match score (e.g., `Match: 94%`) appears in the menu when you're detected

### Keyboard Shortcuts
| Shortcut | Action |
|---|---|
| ⌘ + Shift + L | Panic lock — immediately locks the screen |

---

## Storage Locations

| Type | Path |
|---|---|
| Face embedding | `~/Library/Application Support/FaceGuard/authorized_face.json` |
| Enrolled thumbnail | `~/Library/Application Support/FaceGuard/enrolled_thumbnail.png` |
| App log | `~/Library/Logs/FaceGuard/faceguard.log` |
| Intruder snapshots | `~/Library/Logs/FaceGuard/intruders/` |

---

## Privacy

- ✅ All data is stored locally on your device
- ✅ No network requests are made
- ✅ No face data leaves your Mac
- ✅ Camera is only active when the app is running

---

## Architecture Overview

```
Camera → CameraManager
           ↓ (CVPixelBuffer)
       FrameProcessor  ← (skips 2/3 frames)
           ↓
       FaceDetector  (Vision landmarks → [Float] embedding)
           ↓
       FaceMatcher   (cosine similarity + 5-frame rolling avg)
           ↓                              ↓
    MenuBarController          ScreenLocker + WarningOverlay
```
