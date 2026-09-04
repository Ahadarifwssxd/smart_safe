# SmartSafe — One Tap Emergency App

Complete Flutter application with 10 pages implementing all features from the PowerPoint presentation.

## 🎯 Features Implemented

### Core Pages (10 Total)
1. **Home Page** — SOS button with pulse rings, feature grid, trusted circle, safety tips
2. **SOS Alert Page** — Live alert with countdown, step-by-step checklist, GPS broadcasting
3. **Contacts Page** — Contact cards with online status, SMS/Push badges, add contact
4. **Live Map Page** — GPS grid map with pulsing pin, wave bars, location stats
5. **Safe Route Page** — Time-based filters, color-coded routes (safe/caution/avoid)
6. **Crash Detection Page** — Live accelerometer, sensitivity settings, 4-step crash flow
7. **Alert History Page** — Timeline with filters, color-coded event badges
8. **Notifications Page** — Grouped alerts, unread counter, mark all read
9. **Settings Page** — Profile card, 7 safety toggles, emergency numbers
10. **Add Contact Page** — Live avatar preview, relation selector, SMS/Push toggles

### Animations
- **PulseRing** — 3 expanding rings with fade-out (SOS button, location pin)
- **PulseSOSButton** — Scale pulse animation (1.0 → 1.06)
- **BlinkDot** — Online status indicator with opacity fade
- **WaveBars** — 5-bar staggered wave animation (GPS broadcasting)
- **SlideUpFade** — Page entry animation with configurable delay
- **DotGrid** — Background texture for dark theme

### Color Palette
- **Background:** `#0A0F1E` (deepest navy), `#0F1C2D` (card), `#162032` (panel)
- **Accent:** `#E63946` (red SOS), `#2EC4B6` (teal GPS), `#F4A261` (amber crash)
- **Status:** `#6C63FF` (purple), `#2DC653` (green safe)
- **Text:** `#FFFFFF` (white), `#CBD5E1` (off-white), `#64748B` (muted)

## 📦 Installation

### Prerequisites
- Flutter SDK 3.0.0 or higher
- Dart 3.0.0 or higher
- Android Studio / VS Code with Flutter extensions

### Setup Steps

1. **Unzip the project**
```bash
unzip SmartSafe_Complete.zip
cd smartsafe_complete
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Run the app**
```bash
# On Android emulator/device
flutter run

# On iOS simulator (macOS only)
flutter run -d ios

# On Chrome (web)
flutter run -d chrome
```

## 🗂️ Project Structure

```
smartsafe_complete/
├── lib/
│   ├── main.dart                    # App entry + bottom nav (9 pages)
│   ├── theme/
│   │   └── colors.dart              # AppColors + AppTheme (dark mode)
│   ├── models/
│   │   └── models.dart              # Contact, AlertEvent, AppNotif, RouteSegment, SafetyTip
│   ├── widgets/
│   │   └── widgets.dart             # PulseRing, WaveBars, BlinkDot, SlideUpFade, DCard, etc.
│   └── pages/
│       ├── 01_home_page.dart        # Home with SOS button
│       ├── 02_alert_page.dart       # SOS Active + countdown
│       ├── 03_contacts_page.dart    # Trusted circle
│       ├── 04_map_page.dart         # Live GPS map
│       ├── 05_safe_route_page.dart  # Route safety
│       ├── 06_crash_detection_page.dart # Accelerometer + crash flow
│       ├── 07_alert_history_page.dart   # Timeline log
│       ├── 08_notifications_page.dart   # Grouped alerts
│       ├── 09_settings_page.dart        # Profile + safety toggles
│       └── 10_add_contact_page.dart     # Add new contact form
└── pubspec.yaml                     # Dependencies
```

## 🎨 Design System

### Typography
- **Headers:** Arial Black, 22-28px, weight 800
- **Body:** System default, 11-13px, weight 400-500
- **Labels:** Uppercase, 10px, letter-spacing 1.2

### Components
- **Cards:** 12px border radius, subtle borders (opacity 0.06-0.4)
- **Buttons:** 14px radius for big buttons, 20-30px for pills
- **Spacing:** 8px base unit, multiples of 8 (8, 16, 24, 32)

## 📱 Features Breakdown

### Home Page
- Live clock display
- Pulsing SOS button (tap/shake/volume trigger)
- 4 feature cards (GPS, Ambulance, Route, SMS)
- Trusted circle avatars
- Shake-to-alert hint with animation
- 3 safety tips with color-coded icons

### SOS Alert Page
- Triple pulse ring animation
- 30-second countdown arc
- Live step checklist (GPS → Contacts → 1122 → Police)
- GPS broadcasting status with wave bars
- Cancel button (I AM SAFE)

### Contacts Page
- Contact cards with:
  - Avatar with initials
  - Online/Away blinking status dot
  - SMS and Push notification badges
  - Phone number display
- Add contact button (navigates to page 10)
- Shake-to-alert tip card
- SMS backup info card

### Live Map Page
- GPS grid map with custom painter
- Pulsing red location pin
- "LIVE" broadcasting bar with wave animation
- 4 stat cards (Location, Sharing, Nearest help, Accuracy)
- Location tracker footer

### Safe Route Page
- Time filter chips (Now, 6PM, 9PM, 11PM, 1AM)
- Color-coded route map with custom painter
- 3 route cards with safety levels (Safe/Caution/Avoid)
- Night travel warning
- Start navigation button

### Crash Detection Page
- Monitoring status circle
- Live accelerometer bar (animated)
- Sensitivity selector (Low/Medium/High)
- 4-step crash flow visualization
- Test crash button
- 10-second cancel countdown (when triggered)

### Alert History Page
- Filter chips (All, SOS, Crash, Safe, GPS)
- Mini stats row (Total, SOS, Crash, Safe counts)
- Timeline cards with:
  - Color-coded icons
  - Location + timestamp
  - Event type badge
- Empty state with icon

### Notifications Page
- Unread counter badge
- "Mark all read" button
- Grouped notifications (New / Earlier)
- Color-coded event icons
- Tap to mark as read
- Timestamp (relative time)

### Settings Page
- Profile card with avatar
- 7 safety toggles:
  - Shake to SOS
  - Crash detection
  - SMS offline backup
  - Silent SOS mode
  - Night travel alerts
  - Auto-call police
  - Background location
- 3 emergency number buttons (1122, 15, Rescue)
- About section (version, privacy)
- Sign out button

### Add Contact Page
- Live avatar preview (updates as you type)
- Name + phone number fields
- Relation selector (Family/Friend/Work/Other)
- SMS Alert toggle
- App Push Notification toggle
- Info card about alert behavior
- Save button with validation

## 🚀 Next Steps (Production Ready)

### Required Permissions (Android)
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.SEND_SMS" />
<uses-permission android:name="android.permission.CALL_PHONE" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### Required Permissions (iOS)
Add to `ios/Runner/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>SmartSafe needs your location to share with emergency contacts</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>SmartSafe needs background location for crash detection</string>
```

### Recommended Packages
```yaml
dependencies:
  geolocator: ^10.1.0           # GPS tracking
  telephony: ^0.2.0             # SMS sending
  url_launcher: ^6.2.1          # Phone dialing
  sensors_plus: ^4.0.0          # Accelerometer (crash detection)
  flutter_local_notifications: ^16.2.0  # Push notifications
  shared_preferences: ^2.2.2    # Local storage
  provider: ^6.1.1              # State management
```

## 📝 Notes

- All animations tested on 60fps
- Dark theme optimized for OLED screens
- Bottom nav scrolls horizontally for 9 tabs
- All pages have entry animations (SlideUpFade)
- No external API calls — fully functional UI/UX demo
- Ready for backend integration

## 👨‍💻 Developer

Built with Flutter 3.0+  
Dark theme: Night Guardian palette  
Animations: 100% custom StatefulWidget  
Total Pages: 10  
Total Widgets: 25+  
Total Animations: 6  

---

**SmartSafe** — Because every second counts. 🆘
