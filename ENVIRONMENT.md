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

### Six-digit email OTP

1. In Supabase, open **Authentication → Email Templates**.
2. Edit the **Magic Link / OTP** template.
3. Include `{{ .Token }}` in the email body, for example:

```html
<h2>Your YEET login code</h2>
<p>Enter this code: {{ .Token }}</p>
```

4. Confirm the Email provider is enabled under **Authentication → Sign In / Providers**.
5. Configure a production SMTP provider before public launch if you do not want to rely on Supabase's limited default email delivery.

## Final checklist

- `apps/web/.env.local` exists locally and is ignored by Git.
- Vercel contains only the two `VITE_` variables.
- Supabase Edge Function secrets contain `WEB_ALLOWED_ORIGINS`.
- Supabase URL Configuration contains production, localhost, and preview callbacks.
- Google Client Secret exists only in Google/Supabase configuration.
- The email template contains `{{ .Token }}`.
