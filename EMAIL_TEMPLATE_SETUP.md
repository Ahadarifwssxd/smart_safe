# Professional Emails — EmailJS Setup (1 minute)

The app now builds fully branded, professional HTML for every email
(verification, SOS alert, "I am safe") in code and passes it as a single
variable: **`message_html`**.

For these to render, your EmailJS template must output that variable as **raw
HTML** (triple curly braces). Do this once:

### Steps
1. Open https://dashboard.emailjs.com/ → **Email Templates**
2. Open the template used by the app: **`template_hm96mph`**
3. Go to the **Content** tab and switch the editor to **Code / HTML** (the `</>` button).
4. Replace the entire body with exactly:

   ```
   {{{message_html}}}
   ```

   ⚠️ Three braces `{{{ }}}`, not two — two braces escapes the HTML and you'd
   see raw tags.

5. Set the **Subject** field to:

   ```
   {{subject}}
   ```

6. (Optional) Set **From Name** to `SmartSafe` and a verified **Reply-To**.
7. **Save**.

That's it. Verification, SOS, and cancel emails will now all use the branded
SmartSafe layout. The look is controlled entirely from
`lib/services/email_send_service.dart` going forward — no more dashboard edits
needed to tweak wording or design.

### Variables the app sends (for reference)
`message_html` (full branded HTML), `subject`, `title`, `code`,
`verification_code`, `user_name`, `name`, `to_email`, `time`, `app_name`,
`message` (plain-text fallback).

### Cloud Function emails
The verification + SOS emails sent from Firebase Functions (Resend/SMTP) are
already branded in `functions/index.js`. Deploy with:

```
firebase deploy --only functions
```
