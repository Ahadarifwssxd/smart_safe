# SmartSafe Billing Setup Guide

This guide walks you through setting up the subscription system for SmartSafe Premium using **RevenueCat** and **Google Play Billing**.

---

## Overview

SmartSafe uses a **Freemium + Subscription** model:
- **Free tier**: Basic SOS, panic toolkit, safe route, 3 emergency contacts, 20 chatbot messages/day
- **Premium tier**: Everything in free + crash detection, live tracking history, unlimited contacts, unlimited chatbot, danger-zone alerts

RevenueCat handles:
- Google Play Billing integration
- Receipt validation
- Subscription lifecycle (renewals, cancellations, refunds)
- Analytics and webhooks

You just need to:
1. Create a RevenueCat account
2. Set up products in Google Play Console
3. Configure RevenueCat to read those products
4. Paste the API key into the app

---

## Step 1: Create RevenueCat Account

1. Go to [https://app.revenuecat.com](https://app.revenuecat.com)
2. Sign up for a free account (no credit card required)
3. Create a new project:
   - Project name: **SmartSafe**
   - Platform: **Android**
   - Package name: `com.example.smartSafe` (or your actual package)

---

## Step 2: Create Products in Google Play Console

1. Go to [https://play.google.com/console](https://play.google.com/console)
2. Select your SmartSafe app (or create one if it doesn't exist)
3. Navigate to **Monetize → Products → Subscriptions**
4. Create two subscription products:

### Product 1: Monthly Premium
- **Product ID**: `smartsafe_premium_monthly`
- **Name**: SmartSafe Premium Monthly
- **Description**: Unlock all premium features including crash detection, live tracking history, unlimited contacts, and more
- **Price**: PKR 299/month (or equivalent in your currency)
- **Free trial**: 7 days

### Product 2: Yearly Premium
- **Product ID**: `smartsafe_premium_yearly`
- **Name**: SmartSafe Premium Yearly
- **Description**: Unlock all premium features for a full year
- **Price**: PKR 2,999/year (15% discount vs monthly)
- **Free trial**: 7 days

5. **Activate** both products (they must be "Active" status)

---

## Step 3: Connect Google Play to RevenueCat

1. In RevenueCat dashboard, go to **Project → Integrations → Google Play**
2. Follow the setup wizard:
   - You'll need to create a **Service Account** in Google Cloud Console
   - Download the JSON key file
   - Upload it to RevenueCat
3. RevenueCat will verify the connection (takes ~5 minutes)

**Detailed steps for Service Account:**
1. Go to [https://console.cloud.google.com](https://console.cloud.google.com)
2. Select your project (or create one)
3. Navigate to **IAM & Admin → Service Accounts**
4. Create a new service account:
   - Name: `revenuecat-service-account`
   - Role: **Pub/Sub Subscriber** (read-only access to purchases)
5. Create a key (JSON format) and download it
6. Upload this JSON file to RevenueCat

---

## Step 4: Create Entitlement in RevenueCat

1. In RevenueCat dashboard, go to **Project → Entitlements**
2. Create a new entitlement:
   - **Identifier**: `premium` (must match exactly — case-sensitive)
   - **Display name**: Premium
3. Attach both products to this entitlement:
   - `smartsafe_premium_monthly`
   - `smartsafe_premium_yearly`

---

## Step 5: Get Your RevenueCat API Key

1. In RevenueCat dashboard, go to **Project → Settings → API Keys**
2. Copy the **Android** API key (starts with `goog_...`)
3. Open `lib/config/revenue_cat_config.dart`
4. Replace the placeholder with your actual key:

```dart
static const String androidApiKey = 'goog_YOUR_ACTUAL_KEY_HERE';
```

---

## Step 6: Test with Sandbox Accounts

Before publishing, test the purchase flow with sandbox accounts:

1. In Google Play Console, go to **Setup → License testing**
2. Add test email addresses (your own Gmail, team members, etc.)
3. In Google Play Console, go to **Testing → Internal testing**
4. Create an internal test track and upload your APK
5. Install the app from the internal test link
6. Try purchasing — you won't be charged (sandbox mode)

**Test scenarios:**
- Purchase monthly plan → verify Firestore updates
- Purchase yearly plan → verify Firestore updates
- Cancel subscription → verify features lock again
- Restore purchases → verify it works after reinstall
- Let trial expire → verify features lock

---

## Step 7: Publish to Production

Once testing is complete:

1. In Google Play Console, promote your app from **Internal testing** to **Production**
2. RevenueCat automatically switches from sandbox to production mode
3. Real users can now purchase subscriptions

---

## Pricing Suggestions

| Plan | Price (PKR) | Price (USD) | Notes |
|------|-------------|-------------|-------|
| Monthly | 299 | ~$1.00 | Standard monthly billing |
| Yearly | 2,999 | ~$10.00 | 15% discount, billed annually |

Adjust prices in Google Play Console anytime — no app update needed.

---

## Feature Gating

The app gates these features behind Premium:

| Feature | Free | Premium |
|---------|------|---------|
| SOS Alert | ✅ | ✅ |
| Panic Toolkit | ✅ | ✅ |
| Safe Route (basic) | ✅ | ✅ |
| Emergency Contacts | 3 max | Unlimited |
| Chatbot Messages | 20/day | Unlimited |
| Crash Detection | ❌ | ✅ |
| Live Tracking History | ❌ | ✅ |
| Danger Zone Alerts | ❌ | ✅ |

To add/remove gated features, edit `lib/models/subscription_plan.dart`.

---

## Troubleshooting

### "RevenueCat API key not configured" error
- Check that you pasted the key in `lib/config/revenue_cat_config.dart`
- Verify the key starts with `goog_` (Android key, not iOS)

### "Failed to load pricing" on paywall screen
- Ensure products are **Active** in Google Play Console
- Check that RevenueCat is connected to Google Play (Project → Integrations)
- Verify product IDs match exactly: `smartsafe_premium_monthly` and `smartsafe_premium_yearly`

### Purchases not restoring
- User must be logged into the same Google account on the device
- Check Google Play Console → Order history for the purchase
- Try "Restore purchases" from the paywall or management screen

### Firestore not updating after purchase
- Check Firebase Console → Firestore → users/{uid} document
- Look for `plan`, `planExpiresAt`, `isInTrial` fields
- Check Flutter console for `SubscriptionService` logs

---

## Support

- **RevenueCat docs**: [https://docs.revenuecat.com](https://docs.revenuecat.com)
- **Google Play Billing**: [https://developer.android.com/google/play/billing](https://developer.android.com/google/play/billing)
- **SmartSafe issues**: Check Flutter console logs and Firebase Firestore data

---

## Revenue & Analytics

RevenueCat provides:
- **MRR (Monthly Recurring Revenue)**: Dashboard → Overview
- **Churn rate**: Dashboard → Customers → Churn
- **Trial conversion**: Dashboard → Customers → Trials
- **Refunds**: Dashboard → Customers → Refunds

No additional setup needed — all tracked automatically.

---

## Legal & Tax Notes

- **Google/Apple take**: 15% for small developers (<$1M/year revenue), 30% above that
- **Tax handling**: Google/Apple handle sales tax collection for most regions
- **Privacy policy**: Update your privacy policy to mention subscription data
- **Terms of service**: Add subscription terms (auto-renewal, cancellation policy)

---

## Next Steps

After setup is complete:
1. Test the full purchase flow (purchase → verify features unlock → cancel → verify features lock)
2. Monitor RevenueCat dashboard for first purchases
3. Consider adding iOS support (Phase 2)
4. Consider adding Family/Enterprise plans (Phase 2)

---

**Questions?** Check the RevenueCat docs or open an issue in the SmartSafe repo.
