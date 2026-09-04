import 'package:flutter/material.dart';
import '../pages/28_enhanced_community_sos_page.dart';
import '../theme/colors.dart';

/// Quick integration example for Live Tracking Community SOS
///
/// Use this widget anywhere in your app to launch the Live Tracking SOS
///
/// Example usage:
/// ```dart
/// // In your home page or emergency hub
/// LiveTrackingSOSLauncher()
/// ```

class LiveTrackingSOSLauncher extends StatelessWidget {
  final VoidCallback? onCancel;
  final String? label;

  const LiveTrackingSOSLauncher({
    Key? key,
    this.onCancel,
    this.label = 'Community SOS\nwith Live Tracking',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        EnhancedCommunitySosPage.open(
          context,
          onCancel: onCancel,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              C.accent.withValues(alpha: 0.9),
              C.accent.withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: C.accent.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sos_rounded, color: Colors.white, size: 40),
            const SizedBox(height: 8),
            Text(
              label ?? 'Community SOS',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Live Map + Helpers',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Example: Add to your Emergency Hub or Home Page
class CommunitySOSExample extends StatelessWidget {
  const CommunitySOSExample({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Emergency Response',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // Live Tracking SOS Option
        LiveTrackingSOSLauncher(
          onCancel: () {
            print('SOS cancelled');
          },
        ),

        const SizedBox(height: 12),

        // Other emergency options...
        GestureDetector(
          onTap: () {
            // Open other emergency feature
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.bg2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.success.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency Services',
                        style: TextStyle(
                          color: C.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Call 1122 Rescue',
                        style: TextStyle(
                          color: C.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Navigation Integration Example
/// 
/// Add this to your main navigation/routing file
/// 
/// ```dart
/// import 'services/live_tracking_service.dart';
/// import 'pages/28_enhanced_community_sos_page.dart';
/// 
/// // In your app initialization
/// void main() {
///   // ... other initialization
///   
///   // Initialize Live Tracking Service
///   LiveTrackingService();
///   
///   runApp(const MyApp());
/// }
/// ```

/// Firebase Integration Checklist
/// 
/// Before using Live Tracking SOS, ensure:
/// 
/// ✅ 1. Add these security rules to your firestore.rules:
/// ```
/// match /live_tracking/{userId} {
///   allow read: if request.auth.uid != null;
///   allow write: if request.auth.uid == userId;
///   allow delete: if request.auth.uid == userId;
/// }
/// 
/// match /sos_alerts/{document=**} {
///   allow read: if request.auth.uid != null;
///   allow write: if request.auth.uid != null;
/// }
/// 
/// match /notifications/{document=**} {
///   allow read: if request.auth.uid == resource.data.targetUserId;
///   allow write: if request.auth.uid != null;
/// }
/// ```
/// 
/// ✅ 2. Update your MainActivity.java for Android location permission:
/// ```java
/// // Already handled by location_service_mobile.dart
/// // Make sure AndroidManifest.xml has:
/// // <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
/// // <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
/// ```
/// 
/// ✅ 3. Update Info.plist for iOS location permission:
/// ```xml
/// <!-- Already handled by location_service_mobile.dart -->
/// <!-- Make sure iOS has proper permission prompts -->
/// ```
