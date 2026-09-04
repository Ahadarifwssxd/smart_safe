const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// ─── Twilio credentials ────────────────────────────────────────────────────
const TWILIO_ACCOUNT_SID = "ACeab0b8d5371125e5cd59c2695c4359d8";
const TWILIO_AUTH_TOKEN = "d99dd16f617aa55995073290a8e813a8";
const TWILIO_PHONE_NUMBER = "+15053936316";

// ─── Email transporter (SMTP fallback) ────────────────────────────────────
function createTransporter() {
  const cfg = functions.config().smtp || {};
  const user = cfg.user || process.env.SMTP_USER;
  const pass = cfg.pass || process.env.SMTP_PASS;
  if (!user || !pass) return null;
  return nodemailer.createTransport({
    service: cfg.service || "gmail",
    auth: { user, pass },
  });
}

// ─── Helper: convert Pakistan local number to E.164 ───────────────────────
function toE164(phone) {
  let cleaned = (phone || "").replace(/[\s\-\(\)]/g, "");
  if (cleaned.startsWith("+")) return cleaned;
  if (cleaned.startsWith("0") && cleaned.length === 11)
    return "+92" + cleaned.substring(1);
  if (cleaned.startsWith("3") && cleaned.length === 10)
    return "+92" + cleaned;
  if (cleaned.startsWith("92") && cleaned.length === 12)
    return "+" + cleaned;
  return cleaned;
}

// ─── Twilio: Voice Call ────────────────────────────────────────────────────
async function twilioCall(to, voiceMessage) {
  const toFormatted = toE164(to);
  const twiml = `<Response><Say voice="alice">${voiceMessage}</Say></Response>`;
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Calls.json`;
  const authStr = Buffer.from(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`).toString("base64");

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${authStr}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      From: TWILIO_PHONE_NUMBER,
      To: toFormatted,
      Twiml: twiml,
    }).toString(),
  });

  const data = await response.json();
  if (response.ok) {
    console.log(`✅ Call initiated to ${toFormatted}, SID=${data.sid}`);
    return true;
  } else {
    console.error(`❌ Call FAILED to ${toFormatted}:`, JSON.stringify(data));
    return false;
  }
}

// ─── Twilio: SMS ───────────────────────────────────────────────────────────
async function twilioSms(to, smsBody) {
  const toFormatted = toE164(to);
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`;
  const authStr = Buffer.from(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`).toString("base64");

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${authStr}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      From: TWILIO_PHONE_NUMBER,
      To: toFormatted,
      Body: smsBody,
    }).toString(),
  });

  const data = await response.json();
  if (response.ok) {
    console.log(`✅ SMS sent to ${toFormatted}, SID=${data.sid}`);
    return true;
  } else {
    console.error(`❌ SMS FAILED to ${toFormatted}:`, JSON.stringify(data));
    return false;
  }
}

// ─── Email: via Resend ─────────────────────────────────────────────────────
async function sendSosEmailViaResend(email, senderName, location) {
  const key = functions.config().resend?.key || process.env.RESEND_API_KEY;
  if (!key) {
    console.log("No Resend API key — skipping Resend email.");
    return false;
  }
  const from = functions.config().resend?.from || "SmartSafe <onboarding@resend.dev>";
  const subject = `🚨 EMERGENCY SOS from ${senderName} — SmartSafe`;
  const html = `
    <div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;border:3px solid #e63946;border-radius:12px;overflow:hidden;">
      <div style="background:#e63946;padding:20px;text-align:center;">
        <h1 style="color:#fff;margin:0;font-size:28px;">🚨 EMERGENCY SOS</h1>
        <p style="color:#fff;margin:4px 0 0;font-size:16px;">from SmartSafe</p>
      </div>
      <div style="padding:28px;">
        <p style="font-size:18px;font-weight:bold;color:#1d3557;">${senderName} needs immediate help!</p>
        <p style="font-size:15px;color:#333;">An emergency SOS alert has been triggered.</p>
        <div style="background:#fff3cd;border:1px solid #ffc107;border-radius:8px;padding:16px;margin:20px 0;">
          <p style="margin:0;font-size:15px;"><strong>📍 Location:</strong> ${location}</p>
        </div>
        <p style="font-size:15px;color:#333;">Please contact them immediately or call emergency services.</p>
        <p style="font-size:12px;color:#999;margin-top:32px;border-top:1px solid #eee;padding-top:12px;">Automated alert from the SmartSafe app.</p>
      </div>
    </div>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to: [email], subject, html }),
  });
  if (res.ok) {
    console.log(`✅ SOS email sent to ${email} via Resend`);
    return true;
  }
  console.error(`❌ Resend email FAILED for ${email}:`, await res.text());
  return false;
}

// ─── Email: via SMTP ───────────────────────────────────────────────────────
async function sendSosEmailViaSMTP(email, senderName, location) {
  const transporter = createTransporter();
  if (!transporter) {
    console.log("No SMTP configured — skipping SMTP email.");
    return false;
  }
  const from = functions.config().smtp?.from || transporter.options.auth.user;
  await transporter.sendMail({
    from: `SmartSafe <${from}>`,
    to: email,
    subject: `🚨 EMERGENCY SOS from ${senderName} — SmartSafe`,
    text: `EMERGENCY! ${senderName} needs immediate help!\n\nLocation: ${location}\n\nThis alert was sent by SmartSafe.`,
  });
  console.log(`✅ SOS email sent to ${email} via SMTP`);
  return true;
}

// ─── CALLABLE: triggerSos ─────────────────────────────────────────────────
// Flutter app calls this. It runs on server — no CORS issues.
// Triggers Twilio call + SMS + Email for each contact.
exports.triggerSos = functions.https.onCall(async (data, context) => {
  const { contacts, senderName, location } = data;

  if (!contacts || !Array.isArray(contacts) || contacts.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "contacts array is required.");
  }

  console.log(`🚨 SOS by "${senderName}" at "${location}" — ${contacts.length} contact(s).`);

  const results = [];

  for (const contact of contacts) {
    const { phone, email, name } = contact;
    const result = { name, callSent: false, smsSent: false, emailSent: false };

    const voiceMsg = `This is an emergency S O S alert from Smart Safe. ${senderName} needs immediate help. Their location is: ${location}. Please respond immediately.`;
    const smsMsg = `🚨 SmartSafe EMERGENCY!\n${senderName} has triggered an SOS alert and needs immediate help!\n\n📍 Location: ${location}\n\nPlease call them now!`;

    if (phone) {
      result.callSent = await twilioCall(phone, voiceMsg).catch((e) => {
        console.error("Call error:", e.message);
        return false;
      });
      result.smsSent = await twilioSms(phone, smsMsg).catch((e) => {
        console.error("SMS error:", e.message);
        return false;
      });
    }

    if (email && email.includes("@")) {
      result.emailSent =
        (await sendSosEmailViaResend(email, senderName, location).catch(() => false)) ||
        (await sendSosEmailViaSMTP(email, senderName, location).catch(() => false));
    }

    results.push(result);
  }

  console.log("SOS dispatch done:", JSON.stringify(results));
  return { success: true, results };
});

// ─── FIRESTORE TRIGGER: Email verification ────────────────────────────────
exports.sendEmailVerificationCode = functions.firestore
  .document("email_verifications/{docId}")
  .onCreate(async (snap) => {
    const data = snap.data();
    const email = data.email;
    const code = data.code;
    if (!email || !code) {
      console.error("Missing email or code");
      return null;
    }

    // Try Resend first
    const key = functions.config().resend?.key || process.env.RESEND_API_KEY;
    if (key) {
      const from = functions.config().resend?.from || "SmartSafe <onboarding@resend.dev>";
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from,
          to: [email],
          subject: "Your SmartSafe verification code",
          html: `
          <div style="margin:0;padding:24px 0;background:#f4f6f8;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#fff;border-radius:14px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.06);">
                <tr><td style="background:#0E7C7B;padding:22px 28px;color:#fff;font-size:20px;font-weight:700;">🛡️ SmartSafe</td></tr>
                <tr><td style="padding:32px 28px;color:#1f2933;font-size:15px;line-height:1.6;">
                  <p style="margin:0 0 24px;color:#52606d;">Use the verification code below to confirm your SmartSafe account.</p>
                  <div style="text-align:center;margin:0 0 24px;">
                    <div style="display:inline-block;background:#e9f5f5;border:1px solid #bfe0df;border-radius:12px;padding:18px 28px;font-size:34px;font-weight:800;letter-spacing:10px;color:#0E7C7B;">${code}</div>
                  </div>
                  <p style="margin:0 0 6px;color:#52606d;">This code expires in <strong>10 minutes</strong>.</p>
                  <p style="margin:0;color:#90a0ad;font-size:13px;">If you didn't request this, you can safely ignore this email.</p>
                </td></tr>
                <tr><td style="padding:18px 28px;background:#f0f2f4;color:#90a0ad;font-size:12px;text-align:center;">Automated message from SmartSafe · Please do not reply.</td></tr>
              </table>
            </td></tr></table>
          </div>`,
        }),
      });
      if (res.ok) {
        console.log(`Verification email sent to ${email} via Resend`);
        return null;
      }
    }

    // SMTP fallback
    const transporter = createTransporter();
    if (!transporter) {
      console.log(`[No provider] Code for ${email}: ${code}`);
      return null;
    }
    const from = functions.config().smtp?.from || transporter.options.auth.user;
    await transporter.sendMail({
      from: `SmartSafe <${from}>`,
      to: email,
      subject: "SmartSafe – Your email verification code",
      text: `Your SmartSafe verification code is: ${code}\n\nValid for 10 minutes.`,
    });
    console.log(`Verification email sent to ${email} via SMTP`);
    return null;
  });

// ─── FIRESTORE TRIGGER: Community SOS push ────────────────────────────────
// When the app writes a `notifications` doc of type "sos_alert" for a nearby
// user, deliver it as a real FCM push so they're alerted even if the app is
// closed/backgrounded. Tokens are stored on `users/{uid}.fcmTokens`.
exports.pushCommunitySosAlert = functions.firestore
  .document("notifications/{notifId}")
  .onCreate(async (snap) => {
    const data = snap.data() || {};
    // Handle BOTH community SOS (nearby) and personal SOS (to your emergency
    // contacts) — both should push even when the app is closed.
    const isPersonal = data.type === "sos_personal";
    if (data.type !== "sos_alert" && !isPersonal) return null;

    const targetUserId = data.targetUserId;
    if (!targetUserId) return null;

    const userDoc = await admin
      .firestore()
      .collection("users")
      .doc(targetUserId)
      .get();
    const tokens = (userDoc.data() || {}).fcmTokens || [];
    if (!Array.isArray(tokens) || tokens.length === 0) {
      console.log(`No FCM tokens for ${targetUserId} — skipping push.`);
      return null;
    }

    const senderName = data.senderName || (isPersonal ? "Your contact" : "Someone nearby");
    const message = {
      tokens,
      notification: {
        title: isPersonal
          ? `🆘 ${senderName} needs help!`
          : `🆘 Community SOS — ${senderName} needs help nearby`,
        body: isPersonal
          ? "Your emergency contact triggered an SOS. Tap to see details."
          : "Someone in the community needs help. Tap to respond.",
      },
      data: {
        type: String(data.type || "sos_alert"),
        sosUserId: String(data.sosUserId || ""),
        latitude: String(data.latitude || ""),
        longitude: String(data.longitude || ""),
      },
      android: {
        priority: "high",
        // Render on the app's high-importance channel so the alert pops as a
        // heads-up notification even when the app is closed.
        notification: { channelId: "sos_alerts", sound: "default", priority: "high" },
      },
    };

    try {
      const res = await admin.messaging().sendEachForMulticast(message);
      console.log(
        `Community SOS push → ${targetUserId}: ${res.successCount} ok, ${res.failureCount} failed`
      );

      // Prune tokens that are no longer valid so the array stays clean.
      const stale = [];
      res.responses.forEach((r, i) => {
        if (
          !r.success &&
          r.error &&
          (r.error.code === "messaging/registration-token-not-registered" ||
            r.error.code === "messaging/invalid-registration-token")
        ) {
          stale.push(tokens[i]);
        }
      });
      if (stale.length) {
        await userDoc.ref.update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...stale),
        });
      }
    } catch (e) {
      console.error("Community SOS push failed:", e.message);
    }
    return null;
  });

// ─── FIRESTORE TRIGGER: Community route-hazard report → notify nearby users ──
// When ANY user reports a road hazard (accident/robbery/blocked…), push an
// alert to nearby users so they can avoid that route. Public/community-wide.
function distanceKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

exports.pushRouteHazardAlert = functions.firestore
  .document("route_hazards/{id}")
  .onCreate(async (snap) => {
    const d = snap.data() || {};
    const lat = d.latitude;
    const lon = d.longitude;
    if (typeof lat !== "number" || typeof lon !== "number") return null;

    const reporterId = d.userId || "";
    const type = (d.type || "hazard").toString();
    const place = d.locationName || "a nearby route";
    const when = (d.createdAt && d.createdAt.toDate)
      ? d.createdAt.toDate()
      : new Date();
    const stamp = when.toLocaleString("en-GB", { timeZone: "Asia/Karachi" });

    // Route hazards are PUBLIC community info — notify ALL SmartSafe users
    // (everyone, all over), not just nearby ones. (Personal SOS alerts, by
    // contrast, only go to the user's own emergency contacts.)
    const usersSnap = await admin.firestore().collection("users").get();
    const tokens = [];
    usersSnap.forEach((u) => {
      if (u.id === reporterId) return;
      const m = u.data() || {};
      const arr = m.fcmTokens;
      if (!Array.isArray(arr) || arr.length === 0) return;
      tokens.push(...arr);
    });

    if (tokens.length === 0) {
      console.log("Route hazard: no recipients.");
      return null;
    }

    const title = "⚠️ Hazard reported nearby";
    const body = `${type.charAt(0).toUpperCase() + type.slice(1)} near ${place} — avoid this route. (${stamp})`;

    // FCM caps multicast at 500 tokens per call — chunk it.
    for (let i = 0; i < tokens.length; i += 500) {
      const batch = tokens.slice(i, i + 500);
      try {
        await admin.messaging().sendEachForMulticast({
          tokens: batch,
          notification: { title, body },
          data: {
            type: "route_hazard",
            latitude: String(lat),
            longitude: String(lon),
            hazardType: type,
            reportedAt: stamp,
          },
          android: { priority: "high" },
        });
      } catch (e) {
        console.error("Route hazard push failed:", e.message);
      }
    }
    console.log(`Route hazard push sent to ${tokens.length} token(s).`);
    return null;
  });
