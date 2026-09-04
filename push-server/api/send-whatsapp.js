// SmartSafe — send SOS alerts over WhatsApp using the WhatsApp Business Cloud
// API (Meta). This delivers the message WITHOUT any redirect / without opening
// WhatsApp on the sender's phone. Because the message is business-initiated, it
// MUST use a pre-approved template (see push-server/README.md for setup).
//
// The template carries three body variables:
//   {{1}} = sender name    {{2}} = sender phone    {{3}} = live location link
// so every contact sees WHO needs help, their NUMBER to call back, and WHERE.
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(
      JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
    ),
  });
}

const GRAPH = "https://graph.facebook.com/v21.0";

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "POST only" });
    return;
  }

  try {
    const body = req.body || {};
    const { idToken, senderName, senderPhone, location } = body;
    const recipients = Array.isArray(body.recipients) ? body.recipients : [];

    if (!idToken || recipients.length === 0) {
      res.status(400).json({ error: "idToken and recipients required" });
      return;
    }

    // Only a signed-in SmartSafe user may trigger a broadcast.
    await admin.auth().verifyIdToken(idToken);

    const TOKEN = process.env.WHATSAPP_TOKEN;
    const PHONE_ID = process.env.WHATSAPP_PHONE_NUMBER_ID;
    const TEMPLATE = process.env.WHATSAPP_TEMPLATE_NAME || "smartsafe_sos";
    const LANG = process.env.WHATSAPP_TEMPLATE_LANG || "en";
    if (!TOKEN || !PHONE_ID) {
      res.status(500).json({
        error:
          "WhatsApp not configured — set WHATSAPP_TOKEN and WHATSAPP_PHONE_NUMBER_ID in Vercel.",
      });
      return;
    }

    const name = (senderName || "A SmartSafe user").slice(0, 60);
    const phone = (senderPhone || "unknown").slice(0, 40);
    const loc = (location || "location unavailable").slice(0, 300);

    const results = await Promise.all(
      recipients.map(async (to) => {
        const digits = String(to).replace(/[^0-9]/g, "");
        if (!digits) return { to, ok: false, error: "empty number" };
        try {
          const r = await fetch(`${GRAPH}/${PHONE_ID}/messages`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${TOKEN}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              messaging_product: "whatsapp",
              to: digits,
              type: "template",
              template: {
                name: TEMPLATE,
                language: { code: LANG },
                components: [
                  {
                    type: "body",
                    parameters: [
                      { type: "text", text: name },
                      { type: "text", text: phone },
                      { type: "text", text: loc },
                    ],
                  },
                ],
              },
            }),
          });
          const data = await r.json().catch(() => ({}));
          return { to: digits, ok: r.ok, status: r.status, data };
        } catch (e) {
          return { to: digits, ok: false, error: e.message };
        }
      })
    );

    const sent = results.filter((x) => x.ok).length;
    res
      .status(200)
      .json({ ok: true, sent, failed: results.length - sent, results });
  } catch (e) {
    console.error("send-whatsapp failed:", e.message);
    res.status(500).json({ error: e.message });
  }
};
