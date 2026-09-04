# SmartSafe — WhatsApp Direct-to-All Setup Guide

Yeh guide SmartSafe ko WhatsApp Business Cloud API se jodne ke liye hai, taake
SOS par **saare contacts ko ek saath, direct WhatsApp message** chala jaye
(bina redirect, bina tap). Code pehle se ready hai — sirf Meta setup + Vercel
env vars chahiye.

> **Free tier:** Meta 1000 conversations/month free deta hai.
> **Time:** ~30-45 min setup + Meta ka template review (kuch ghante–1 din).

---

## STEP 1 — Meta Developer Account + App

1. Jao: **https://developers.facebook.com/** → **Log In** (Facebook account se)
2. Upar right → **My Apps** → **Create App**
3. Use case: **"Other"** chuno → **Next**
4. App type: **"Business"** → **Next**
5. App name: `SmartSafe` → email daalo → **Create App**

## STEP 2 — WhatsApp Product Add Karo

1. App dashboard mein neeche scroll → **"WhatsApp"** dhoondo → **Set up**
2. Ek **Meta Business Account** select/create karo
3. Ab aapko **"API Setup"** page milega

## STEP 3 — Phone Number ID + Token Lo

API Setup page par:

1. **Phone number ID** — copy karo (yeh `WHATSAPP_PHONE_NUMBER_ID` hai)
   - Shuru mein Meta ek **test number** free deta hai (isse start kar sakte ho)
2. **Temporary access token** — copy karo (24 ghante chalta hai, testing ke liye)
3. **Permanent token ke liye** (production, taake baar-baar na badalna pade):
   - **Business Settings** → **Users** → **System Users** → **Add**
   - System user banao (role: Admin) → **Generate New Token**
   - App select karo → permissions: **`whatsapp_business_messaging`** +
     **`whatsapp_business_management`** → **Generate**
   - Yeh token copy karo (yeh `WHATSAPP_TOKEN` hai) — **kahin safe rakho**

## STEP 4 — Message Template Banao (ZAROORI)

WhatsApp business-initiated message ke liye **approved template** maangta hai.

1. **https://business.facebook.com/wa/manage/message-templates/** kholo
2. **Create Template**
3. Category: **Utility** (ya **Alert Update**)
4. Name: **`smartsafe_sos`** (bilkul yehi — chhote letters)
5. Language: **English** (`en`)
6. **Body** mein yeh daalo (3 variables ke saath):

   ```
   🚨 SMARTSAFE SOS 🚨
   {{1}} needs urgent help and has triggered an emergency SOS.
   Their phone number: {{2}}
   Live location: {{3}}
   Please call them now or reach their location immediately.
   ```

7. Sample values do (Meta maangega):
   - `{{1}}` = `Ayesha Khan`
   - `{{2}}` = `+923001234567`
   - `{{3}}` = `https://maps.google.com/?q=24.86,67.00`
8. **Submit** → Meta review karega (kuch ghante se 1 din). Status **Approved**
   hone ka intezar karo.

> Template ke 3 body params app se aise jate hain:
> `{{1}}` = sender ka naam, `{{2}}` = sender ka phone, `{{3}}` = location link.
> (Code mein yehi order set hai — badalna nahi.)

## STEP 5 — Vercel mein Env Vars Set Karo

1. **https://vercel.com/** → apna **push-server** project kholo
2. **Settings** → **Environment Variables**
3. Yeh 4 add karo:

   | Name | Value |
   |------|-------|
   | `WHATSAPP_TOKEN` | Step 3 ka permanent token |
   | `WHATSAPP_PHONE_NUMBER_ID` | Step 3 ka phone number ID |
   | `WHATSAPP_TEMPLATE_NAME` | `smartsafe_sos` |
   | `WHATSAPP_TEMPLATE_LANG` | `en` |

4. **Save** → phir **Deployments** → latest deployment → **Redeploy**
   (env vars sirf redeploy ke baad lagti hain)

## STEP 6 — Test

1. SmartSafe app mein 1-2 emergency contact add karo (asli WhatsApp numbers)
2. SOS dabao
3. Un contacts ke WhatsApp par template message aana chahiye — **direct, bina
   kisi redirect ya tap ke** ✅

---

## Troubleshooting

| Error | Wajah / Hal |
|-------|-------------|
| "WhatsApp not configured" | Env vars nahi set / redeploy nahi kiya |
| "Template not found" | Template abhi Approved nahi, ya naam galat |
| Message nahi aaya | Number galat format (E.164 chahiye: +92...), ya test-number mode mein recipient verify karna parta hai |
| Test number restriction | Meta ka free test number sirf **verified** recipients ko bhejta hai. Production ke liye **apna asli business number** add karo (Business verification ke baad) |

---

## Zaroori Notes

- **Test number** se shuru karo (free), phir asli number add karo.
- WhatsApp **utility templates** business-initiated allowed hain (SOS is category mein aata hai).
- Yeh setup **sirf ek baar** karna hai — uske baad har SOS par WhatsApp
  automatically saare contacts ko direct chala jayega.
- **SMS pehle se direct-to-all hai** (SIM se) — WhatsApp optional extra channel hai.

---

## App-side (pehle se ho chuka — kuch nahi karna)

- `lib/services/whatsapp_sender.dart` → Vercel endpoint ko call karta hai
- `push-server/api/send-whatsapp.js` → WhatsApp Business API se saare recipients
  ko template bhejta hai (Promise.all — ek saath sab ko)

Bas Meta setup + Vercel env vars, aur WhatsApp direct-to-all chalu. 🛡️
