# SmartSafe Push Server (FREE — Vercel)

This tiny server sends SOS push notifications to your contacts **even when their
SmartSafe app is closed** — a free replacement for the Blaze-only Firebase
Cloud Function. It runs on Vercel's free tier (no credit card).

The app calls this server on SOS; the server holds the Firebase service account
(kept secret here, never inside the app) and delivers the real FCM push.

---

## One-time setup (~15 minutes)

### 1. Get your Firebase service account key
1. Open [Firebase Console → Project Settings → Service accounts](https://console.firebase.google.com/project/smartsafe-c33bc/settings/serviceaccounts/adminsdk)
2. Click **Generate new private key** → a `.json` file downloads.
3. Keep it safe — you'll paste its contents into Vercel in step 3. **Do NOT commit it to git.**

### 2. Create a free Vercel account + install the CLI
1. Sign up at [vercel.com](https://vercel.com) with GitHub/Google (free, no card).
2. Install the CLI and log in:
   ```powershell
   npm install -g vercel
   vercel login
   ```

### 3. Deploy this folder
From inside `push-server/`:
```powershell
cd "c:\Users\HP Elitebook 820 G3\Downloads\SmartSafe_f4\smart_safe\push-server"
vercel --prod
```
- Accept the defaults when prompted (project name e.g. `smartsafe-push`).
- After it finishes it prints a URL like `https://smartsafe-push.vercel.app`.

### 4. Add the service account as a secret env var
Paste the **entire contents** of the `.json` from step 1 as one env var named
`FIREBASE_SERVICE_ACCOUNT`:
```powershell
vercel env add FIREBASE_SERVICE_ACCOUNT production
```
- When prompted for the value, paste the whole JSON (one line is fine) and press Enter.
- Then redeploy so it picks up the secret:
  ```powershell
  vercel --prod
  ```

> Tip: you can also add it in the Vercel dashboard → your project → **Settings → Environment Variables**.

### 5. Point the app at your URL
Open `lib/services/push_sender.dart` and set:
```dart
static const String endpoint = 'https://smartsafe-push.vercel.app/api/send-sos';
```
(use YOUR Vercel URL + `/api/send-sos`). Rebuild the app.

---

---

## WhatsApp auto-send setup (Meta WhatsApp Business Cloud API)

This sends the SOS over WhatsApp with **no redirect** (server-side). Messages go
from a **business number** (not the user's personal WhatsApp) and must use an
**approved template**.

### 1. Create a WhatsApp app
1. Go to [developers.facebook.com](https://developers.facebook.com/apps) → **Create App** → type **Business**.
2. In the app dashboard, **Add product → WhatsApp → Set up**.
3. You get a free **test phone number**, a **Phone number ID**, and a temporary token.

### 2. Get a token + phone number id
- **Phone number ID**: WhatsApp → API Setup → copy "Phone number ID".
- **Token**: the temporary token expires in 24h. For a permanent one, create a
  **System User** (Business Settings → Users → System Users → Add → Admin),
  generate a token with the `whatsapp_business_messaging` permission.

### 3. Add recipient numbers (test mode)
In test mode WhatsApp only delivers to numbers you add: API Setup → "To" →
**Manage phone number list** → add each contact's number (they confirm via a code).
> To message ANY number, add a real business number + complete business verification.

### 4. Create the message template
WhatsApp Manager → **Message templates → Create template**:
- Name: `smartsafe_sos`  ·  Category: **Utility**  ·  Language: **English**
- Body (exactly 3 variables, in this order — name, phone, location):
  ```
  🆘 SmartSafe Emergency Alert

  {{1}} needs urgent help right now and has triggered an SOS.

  📞 Call them immediately: {{2}}
  📍 Their live location: {{3}}

  Please respond, or call Police 15 / Rescue 1122.
  ```
- Submit → approval usually takes a few minutes.

### 5. Give these to your dev to set on Vercel
- `WHATSAPP_TOKEN` = the access token
- `WHATSAPP_PHONE_NUMBER_ID` = the phone number id
- `WHATSAPP_TEMPLATE_NAME` = `smartsafe_sos` (only if you named it differently)
- `WHATSAPP_TEMPLATE_LANG` = `en` (or `en_US` — match the template's language)

They're added with:
```powershell
vercel env add WHATSAPP_TOKEN production --scope <scope> --token <vercelToken>
vercel env add WHATSAPP_PHONE_NUMBER_ID production --scope <scope> --token <vercelToken>
```
then redeploy.

---

## Test it
1. Install the app on **two** phones, log in on both (so both save FCM tokens).
2. Make them each other's emergency contact (same phone numbers as their logins).
3. **Fully close** the app on phone B (swipe it out of recents).
4. Trigger **SOS** on phone A.
5. Phone B should get a `🆘 ... needs help!` heads-up notification. ✅

## Troubleshooting
- Check the server logs: Vercel dashboard → your project → **Logs**.
- `sent: 0, note: "no device tokens"` → the contact never opened/logged into the
  app on that device, so no token was saved. Open + log in once.
- Nothing arrives but `sent: 1` → battery optimization is killing FCM on the
  receiver (common on Xiaomi/Oppo/Vivo). Set SmartSafe to "unrestricted battery".
