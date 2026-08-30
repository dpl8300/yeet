# YEET environment setup

There are two browser values and one Edge Function setting. None of the values placed in Vercel are secrets because every `VITE_` value is compiled into the public browser bundle.

## 1. Local web app: `apps/web/.env.local`

Create the ignored local file from the committed template:

```sh
cp apps/web/.env.example apps/web/.env.local
```

Fill it with:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME
```

### `VITE_SUPABASE_URL`

1. Open the Supabase Dashboard and select the YEET project.
2. Open **Connect** and copy the Project URL. You can also find it under **Settings → API Keys**.
3. It looks like `https://abcdefghijk.supabase.co`.

This value is public and goes in local Vite and Vercel.

### `VITE_SUPABASE_PUBLISHABLE_KEY`

1. In the same Supabase **Connect** dialog or **Settings → API Keys**, locate **Publishable key**.
2. Create one if the project does not have one yet.
3. Copy the value beginning with `sb_publishable_`.

This key is deliberately safe for browser use when database permissions and RLS are configured. Do not substitute a secret key or the legacy `service_role` key.

## 2. Vercel

In Vercel, select the YEET project, then open **Settings → Environment Variables**. Add:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY
```

Set them separately for Production and Preview. Environment changes apply only to new deployments, so redeploy afterward.

Never add any of these to Vercel:

```text
SUPABASE_SECRET_KEYS
SUPABASE_SERVICE_ROLE_KEY
sb_secret_...
service_role JWTs
Google OAuth client secret
```

### Vercel Web Analytics

In the Vercel project, open **Analytics** and enable **Web Analytics**, then redeploy. The app already includes the official `@vercel/analytics` React integration; there are no analytics environment variables to add.

## 3. Supabase Edge Functions: `WEB_ALLOWED_ORIGINS`

The only custom Edge Function setting is the list of web origins allowed to call YEET functions. Derive it from your real URLs; do not copy the placeholder domain.

```dotenv
WEB_ALLOWED_ORIGINS=http://localhost:5173,https://your-production-domain.com,https://*-your-vercel-team.vercel.app
```

Rules:

- Use origins only: scheme plus host, without paths or trailing slashes.
- Include localhost for development.
- Use the exact production origin.
- Replace `your-vercel-team` with the team or account slug in your Vercel preview URLs.

Set it in **Supabase Dashboard → Edge Functions → Secrets**, or with:

```sh
supabase secrets set 'WEB_ALLOWED_ORIGINS=http://localhost:5173,https://your-production-domain.com,https://*-your-vercel-team.vercel.app'
```

For local Edge Functions, copy the template:

```sh
cp supabase/functions/.env.example supabase/functions/.env
```

Hosted Supabase automatically injects `SUPABASE_URL` and its elevated server keys into Edge Functions. You do not need to retrieve or paste those values. The YEET functions prefer the current `SUPABASE_SECRET_KEYS` value and retain the legacy `SUPABASE_SERVICE_ROLE_KEY` only as a compatibility fallback.

## 4. Authentication settings that are not `.env` values

### Supabase URL configuration

In **Supabase Dashboard → Authentication → URL Configuration**:

- Set **Site URL** to the exact production origin.
- Add `https://your-production-domain.com/auth/callback`.
- Add `http://localhost:5173/**`.
- Add `https://*-your-vercel-team.vercel.app/**` for previews.

The production entry should be exact. Replace every placeholder with your real domain and Vercel team/account slug.

### Google OAuth client ID and secret

These belong in Supabase, not Vercel or the web `.env` file.

1. Open Google Auth Platform and create or select a Google Cloud project.
2. Configure Branding, Audience, and the `openid`, email, and profile scopes.
3. Under **Clients**, create a **Web application** OAuth client.
4. Add your production origin and `http://localhost:5173` as authorized JavaScript origins.
5. In Supabase, open **Authentication → Sign In / Providers → Google** and copy the displayed Supabase callback URL.
6. Add that exact Supabase URL as the Google client's **Authorized redirect URI**. It resembles `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback`.
7. Copy the Google Client ID and Client Secret into the Supabase Google provider screen and enable it.

Vercel preview URLs do not go into Google's redirect-URI list because Google returns to Supabase first. Supabase then returns the user to the app origin.

### Email magic links with Resend

1. In Supabase, open **Authentication → Email Templates**.
2. Edit the **Magic Link / OTP** template.
3. Include `{{ .ConfirmationURL }}` in the email body, for example:

```html
<h2>Sign in to YEET</h2>
<p><a href="{{ .ConfirmationURL }}">Open your secure sign-in link</a></p>
```

4. Confirm the Email provider is enabled under **Authentication → Sign In / Providers**.
5. Keep the Resend integration connected as the production email provider and set the desired Supabase Auth email rate limit.

## 5. `support@yeetphone.com`

Inbound support mail uses Namecheap's free forwarding. Resend remains responsible for outbound replies; do not enable Resend Receiving for the root domain.

### Receive support messages

The live domain already uses Namecheap BasicDNS, the `eforward*.registrar-servers.com` MX records, and Namecheap's forwarding SPF record. Preserve them.

1. Sign in to Namecheap and open **Domain List → yeetphone.com → Manage → Domain**.
2. Find **Redirect Email** and select **Add Forwarder**.
3. Set **Alias** to `support` and **Forward to** to a monitored destination inbox.
4. Save, allow about one hour for activation, and send a test from an address other than the destination inbox.

Do not replace the root-domain MX records with Resend Receiving records. Resend inbound mail is webhook-based and would take over delivery for every address at the domain.

### Send replies through Resend

1. In **Resend → Domains**, confirm that `yeetphone.com` itself is verified for sending. Verification of only `auth.yeetphone.com` does not authorize `support@yeetphone.com`.
2. If needed, add the SPF and DKIM records Resend provides. These sending records can coexist with Namecheap's root forwarding MX records; do not remove or replace the existing root MX records.
3. In **Resend → API Keys**, create `Support SMTP` with **Sending access** restricted to `yeetphone.com`. Do not reuse the key created for Supabase.
4. Store the new key only in the chosen mail client's password/credential storage. Never put it in this repository, Vercel browser variables, or client-side code.
5. Configure a compatible mail client with:

```text
From: YEET Support <support@yeetphone.com>
SMTP host: smtp.resend.com
Port: 465
Security: SSL/TLS
Username: resend
Password: the Support SMTP Resend API key
```

6. Send a reply to an external test address and confirm the message reports passing SPF and DKIM authentication.

Namecheap forwarding is not a full mailbox. Received messages live in the destination inbox, and sent-message history is maintained by the mail client used for Resend SMTP.

## Final checklist

- `apps/web/.env.local` exists locally and is ignored by Git.
- Vercel contains only the two `VITE_` variables.
- Vercel Web Analytics is enabled and the latest deployment reports page views.
- Supabase Edge Function secrets contain `WEB_ALLOWED_ORIGINS`.
- Supabase URL Configuration contains production, localhost, and preview callbacks.
- Google Client Secret exists only in Google/Supabase configuration.
- The email template contains `{{ .ConfirmationURL }}` and Resend delivery is working.
- `support@yeetphone.com` forwards to a monitored inbox and outbound replies authenticate through a separate restricted Resend key.
