// SmartSafe — free closed-app SOS push (drop-in replacement for the Blaze-only
// Cloud Function). Runs on Vercel's free tier. The Firebase service account
// lives here as an env var (never in the app), so only this server can send
// FCM. The app just says "push these user ids"; we look up their device tokens
// and deliver a real FCM notification that shows even when their app is closed.
const admin = require("firebase-admin");

// Initialise once and reuse across warm invocations.
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(
      JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
    ),
  });
}

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "POST only" });
    return;
  }

  try {
    const body = req.body || {};
    const { idToken, type, senderName, sosUserId, latitude, longitude } = body;
    const targetUserIds = Array.isArray(body.targetUserIds)
      ? body.targetUserIds
      : [];

    if (!idToken || targetUserIds.length === 0) {
      res.status(400).json({ error: "idToken and targetUserIds required" });
      return;
    }

    // Security gate: only a signed-in SmartSafe user may trigger a push.
    await admin.auth().verifyIdToken(idToken);

    const isPersonal = type === "sos_personal";
    const db = admin.firestore();

    // Collect every target's FCM tokens, remembering the owner of each token so
    // we can prune dead ones afterwards.
    const tokenOwners = []; // [{ token, uid }]
    await Promise.all(
      targetUserIds.map(async (uid) => {
        const snap = await db.collection("users").doc(uid).get();
        const toks = (snap.data() || {}).fcmTokens || [];
        if (Array.isArray(toks)) {
          toks.forEach((t) => t && tokenOwners.push({ token: t, uid }));
        }
      })
    );

    if (tokenOwners.length === 0) {
      res.status(200).json({ ok: true, sent: 0, note: "no device tokens" });
      return;
    }

    const name = senderName || (isPersonal ? "Your contact" : "Someone nearby");
    const tokens = tokenOwners.map((o) => o.token);
    const message = {
      tokens,
      notification: {
        title: isPersonal
          ? `🆘 ${name} needs help!`
          : `🆘 Community SOS — ${name} needs help nearby`,
        body: isPersonal
          ? "Your emergency contact triggered an SOS. Tap to see details."
          : "Someone in the community needs help. Tap to respond.",
      },
      data: {
        type: String(type || "sos_alert"),
        sosUserId: String(sosUserId || ""),
        latitude: String(latitude || ""),
        longitude: String(longitude || ""),
      },
      android: {
        priority: "high",
        // High-importance channel (pre-created in the app) so the alert pops as
        // a heads-up notification even when the app is fully closed.
        notification: {
          channelId: "sos_alerts",
          sound: "default",
          priority: "high",
        },
      },
    };

    const r = await admin.messaging().sendEachForMulticast(message);

    // Prune tokens FCM reports as permanently dead, grouped per owner.
    const staleByUid = {};
    r.responses.forEach((resp, i) => {
      if (
        !resp.success &&
        resp.error &&
        [
          "messaging/registration-token-not-registered",
          "messaging/invalid-registration-token",
        ].includes(resp.error.code)
      ) {
        const { uid, token } = tokenOwners[i];
        (staleByUid[uid] = staleByUid[uid] || []).push(token);
      }
    });
    await Promise.all(
      Object.entries(staleByUid).map(([uid, toks]) =>
        db
          .collection("users")
          .doc(uid)
          .update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...toks),
          })
      )
    );

    res.status(200).json({ ok: true, sent: r.successCount, failed: r.failureCount });
  } catch (e) {
    console.error("send-sos failed:", e.message);
    res.status(500).json({ error: e.message });
  }
};
