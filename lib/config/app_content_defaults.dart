// ─────────────────────────────────────────────────────────────────────────
//  SINGLE SOURCE OF TRUTH for every page's editable text (headings, subtitles,
//  hero copy, badges, button labels).
//
//  This is the "one file" that makes dashboard → app content easy:
//   • The app reads these as the OFFLINE FALLBACK (page renders even with no
//     network / before Firestore is seeded).
//   • On first run these are copied into the Firestore `page_content` collection
//     (one document per pageKey) so the admin dashboard can edit them live.
//   • Pages read live values through [PageContentService] / [DynText]; whatever
//     the admin types in the dashboard instantly overrides the default here.
//
//  To make ANOTHER page dynamic:
//   1. Add a `'<page_key>': { 'field': 'default text', ... }` entry below.
//   2. In the page, replace `Text('Hard coded')` with
//      `DynText('<page_key>', 'field', 'Hard coded')`.
//  That's it — the dashboard editor lists every page/field automatically.
// ─────────────────────────────────────────────────────────────────────────

/// pageKey → (fieldKey → default text). Keep keys short & stable; they are the
/// Firestore field names the dashboard edits.
const Map<String, Map<String, String>> kPageContentDefaults = {
  // ── Auth ──────────────────────────────────────────────────────────────
  'login': {
    'brand': 'SmartSafe',
    'tagline': 'Stay protected. Always.',
    'heading': 'Welcome back',
    'subheading': 'Login with your email',
    'loginButton': 'Login',
    'googleButton': 'Continue with Google',
    'forgotPassword': 'Forgot password?',
    'signupPrompt': "Don't have an account? Sign up",
  },
  'signup': {
    'brand': 'SmartSafe',
    'tagline': 'Stay protected. Always.',
    'heading': 'Create account',
    'subheading': 'Your safety starts here',
    'signupButton': 'Sign up',
    'loginPrompt': 'Already have an account? Login',
  },
  'forgot_password': {
    'heading': 'Forgot password?',
    'subheading':
        "Enter your registered email. We'll send a 6-digit OTP to verify your identity.",
    'button': 'Send reset link',
  },

  // ── Home ──────────────────────────────────────────────────────────────
  'home': {
    'greeting': 'Stay safe',
    'sosHint': 'Press and hold to send SOS',
    'quickAccessTitle': 'Quick Access',
  },

  // ── Women Safety ──────────────────────────────────────────────────────
  'women_safety': {
    'title': 'Women Safety',
    'badge': 'GUIDE',
    'subtitle': 'Know the signs, stay alert, stay safe',
    'heroEmoji': '💪',
    'heroTitle': 'You are stronger than you think',
    'heroBody':
        'Your safety is your right — not a favour. Trust your instincts, '
            'stay aware, and remember: help is one tap away. SmartSafe is with '
            'you, everywhere you go.',
    'helplinesTitle': '📞 Emergency — Tap to Call',
    'warningsTitle': '⚠️ Warning Signs — Trust Your Instincts',
    'preventionTitle': '🛡️ Prevention — Before You Leave',
    'defenseTitle': '🥊 Self-Defense Basics',
    'carryTitle': '🎒 What to Carry',
    'worstTitle': '🚨 If Worst Happens — Immediate Actions',
    'handSignalsTitle': '🆘 Hand Signals for Help (Voice)',
    'silentSosTitle': 'SmartSafe Silent SOS',
    'silentSosBody':
        "Shake phone 3× to alert all contacts without sound or screen. "
            "Attacker won't notice.",
  },

  // ── Crisis / SOS hubs & tools ─────────────────────────────────────────
  'hub_emergency': {
    'title': 'Crisis Hub',
    'subtitle': 'Emergency Response Control Center',
  },
  'hub_security': {
    'title': 'Security Hub',
    'subtitle': 'Active Sensory Monitors & Incident Records',
  },
  'hub_travel': {
    'title': 'Travel Hub',
    'subtitle': 'Secure Navigation & Route Guard',
  },
  'hub_health': {
    'title': 'Health & Wellness Hub',
    'subtitle': 'Emergency First Aid & Calm Instructors',
  },
  'hub_community': {
    'title': 'Insights & Community',
    'subtitle': 'Safety Metrics, Circle Audits & Public Feeds',
  },
  'community_sos': {
    'title': 'Community SOS',
    'subtitle': 'Alert nearby SmartSafe users — 10 km radius',
    'button': 'Send Community Alert',
  },
  'evidence': {
    'title': 'Evidence Vault',
    'subtitle': 'Record photo, audio & video evidence',
  },
  'emergency_dial': {
    'title': 'Emergency Contacts',
    'subtitle': 'One-tap national helplines',
  },
  'emergency_will': {
    'title': 'Emergency Info',
    'subtitle': 'Private info first responders may need',
  },
  'panic_toolkit': {
    'title': 'Panic Toolkit',
    'subtitle': 'Instant tools for dangerous situations',
  },
  'panic_breathe': {
    'title': 'Panic Breathe',
    'subtitle': 'Breathe to calm your nervous system',
  },

  // ── Travel / security / health pages ──────────────────────────────────
  'danger_zone': {
    'title': 'Danger Zones',
    'subtitle': 'Community-reported unsafe areas',
  },
  'safe_checkin': {
    'title': 'Safe Check-In',
    'subtitle': "Set a timer — we alert your circle if you don't check in",
  },
  'safe_route': {
    'title': 'Plan a safe route',
    'subtitle': 'Checked against flagged danger zones',
  },
  'crash_detection': {
    'title': 'Crash Detection',
    'subtitle': 'Automatic accident alerts while you drive',
  },
  'driving_safety': {
    'title': 'Driving Safety',
    'subtitle': 'Stay alert on the road',
  },
  'child_safety': {
    'title': 'Child Safety',
    'subtitle': 'Keep your children protected',
  },
  'first_aid': {
    'title': 'First Aid Guide',
    'subtitle': 'Step-by-step help for emergencies',
  },
  'nearest_hospitals': {
    'title': 'Nearest Help',
    'subtitle': 'Closest medical help around you',
  },
  'incident_report': {
    'title': 'Report an Incident',
    'subtitle': 'Help keep the community informed',
  },

  // ── Insights & circle ─────────────────────────────────────────────────
  'safety_score': {
    'title': 'Safety Score',
    'subtitle': 'How protected you are right now',
  },
  'family_radar': {
    'title': 'Family Radar',
    'subtitle': "Your circle's live location",
  },
  'alert_history': {
    'title': 'Alert History',
    'subtitle': 'Every alert you have sent or received',
  },
  'my_sos_history': {
    'title': 'My SOS History',
    'subtitle': 'When and where you triggered SOS',
  },
  'safety_feed': {
    'title': 'Safety Feed',
    'subtitle': 'Real-time community updates',
  },

  // ── Contacts / settings / misc ────────────────────────────────────────
  'contacts': {
    'title': 'Emergency Contacts',
    'subtitle': 'People we alert when you need help',
  },
  'add_contact': {
    'title': 'Add Contact',
    'subtitle': 'Add someone to your trusted circle',
  },
  'settings': {
    'title': 'Settings',
    'subtitle': 'App preferences and account',
  },
  'edit_profile': {
    'title': 'Edit Profile',
    'subtitle': 'Update your personal details',
  },
  'notifications': {
    'title': 'Notifications',
    'subtitle': 'Your latest alerts and updates',
  },
  'offline_sms': {
    'title': 'Offline SMS SOS',
    'subtitle': 'Send alerts even without internet',
  },

  // ── Privacy Policy (fully dashboard-editable) ─────────────────────────
  'privacy_policy': {
    'title': 'Privacy Policy',
    'updated': 'Last updated: July 2026',
    's1_title': '1. Who we are',
    's1_body':
        'SmartSafe is a personal-safety app that helps you send SOS alerts, '
            'share your live location with trusted contacts, and reach emergency '
            'services quickly.',
    's2_title': '2. Information we collect',
    's2_body': '• Account: your name, email and phone number.\n'
        '• Location: your GPS location, used only to share with your chosen '
        'contacts during an SOS and to compute safe routes.\n'
        '• Emergency contacts: the names and numbers you add.\n'
        '• Optional: gender, blood group, profile photo, and any evidence '
        '(photo/audio/video) you record.',
    's3_title': '3. How we use it',
    's3_body':
        'Your data is used ONLY to deliver safety features: sending SOS alerts '
            'and your location to your contacts, crash/shake detection, safe '
            'routing, and showing your info to first responders you choose. We '
            'never sell your data.',
    's4_title': '4. Location & background use',
    's4_body':
        'Location is accessed in the background only when you enable it, so '
            'tracking can continue during an emergency even when the screen is '
            'off. You can turn this off any time in Settings.',
    's5_title': '5. Sharing',
    's5_body':
        'We share your location and alert only with the emergency contacts you '
            'add and, for Community SOS, with nearby SmartSafe users you ask for '
            'help. We do not share your data with advertisers.',
    's6_title': '6. Storage & security',
    's6_body':
        'Data is stored securely on Firebase (Google Cloud). Media you record '
            'is uploaded to your configured media provider. Access is protected '
            'by your account login.',
    's7_title': '7. Your choices',
    's7_body':
        'You can edit your profile, remove emergency contacts, delete your SOS '
            'history, and turn off location or background protection at any time '
            'from Settings.',
    's8_title': '8. Contact us',
    's8_body':
        'For any privacy question or a request to delete your data, contact the '
            'SmartSafe team through Settings → Send Feedback.',
    'disclaimer':
        'SmartSafe is a safety aid, not a replacement for official emergency '
            'services. In a real emergency always try to call 1122 / 15 as well.',
  },
};

/// All page keys, handy for the dashboard editor's page picker.
List<String> get kPageContentKeys => kPageContentDefaults.keys.toList()..sort();
