# YEET

YEET is a Vite, React, and TypeScript PWA that measures phone airtime in the browser. It includes guest play, Supabase accounts and leaderboard storage, optional device-local POV recording, branded video sharing, privacy-focused Vercel Web Analytics, offline leaderboard snapshots, and installable Home Screen assets.

The original Swift app remains buildable under `apps/ios/` as the native reference implementation. Web gameplay has no haptics or haptic captions.

## Repository layout

```text
apps/ios/                 Preserved Swift app, Xcode project, and tests
apps/web/                 Vite React PWA and Vercel configuration
packages/airtime-core/    Shared TypeScript detector and trace validation
supabase/                 Migrations, Edge Functions, and pgTAP tests
design/reference/         Original UI and logo reference images
```

## Run the web app

Node 20 or newer is required.

```sh
npm install
cp apps/web/.env.example apps/web/.env.local
npm run dev
```

Open `http://localhost:5173`. Without Supabase variables, gameplay and sensor validation still load, while accounts and the leaderboard report that the backend is unavailable.

Useful checks:

```sh
npm test
npm run typecheck
npm run build
```

The browser requests motion permission directly from the YEET button. During the first second of the countdown, every attempt runs a 500ms stationary preflight with at least 20 finite, monotonic samples, a median magnitude from 0.75g through 1.25g, and a 95th-percentile sample gap no greater than 50ms. Devices that cannot provide reliable motion data cannot play.

## Configure Supabase

For a copy-ready list of every value, where it belongs, and how to obtain it, see [`ENVIRONMENT.md`](ENVIRONMENT.md).

Create `apps/web/.env.local` with public client values only:

```dotenv
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Never put the service-role key in Vercel, a `VITE_` variable, or browser code. Supabase injects `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` into deployed Edge Functions.

Apply every migration in filename order, then deploy both functions:

```sh
supabase link --project-ref your-project-ref
supabase db push
supabase functions deploy submit-attempt --use-api
supabase functions deploy delete-account --use-api
```

The API bundler is intentional: `submit-attempt` imports `packages/airtime-core` from outside the `supabase/` directory so the browser and Edge Function execute one detector implementation.

Set the Edge Function secret `WEB_ALLOWED_ORIGINS` to a comma-separated list of the exact production origin, localhost, and the approved Vercel preview wildcard (for example, `https://yeet.example,http://localhost:5173,https://*-your-team.vercel.app`). `submit-attempt` verifies the access token, rejects traces over 2,500 samples or 20 seconds, re-runs the shared detector, writes only server-derived metrics through a service-only RPC, and never stores the raw trace. The migration revokes direct authenticated access to the former score-writing RPC.

Enable Google and Email providers in Supabase Auth. Configure the Magic Link template with `{{ .ConfirmationURL }}` so it sends a sign-in link rather than a numeric OTP. Set:

- `SITE_URL` to the exact production URL.
- Production redirect to `https://your-domain.example/auth/callback`.
- Local redirect to `http://localhost:5173/**`.
- Preview redirect to `https://*-<team-or-account-slug>.vercel.app/**`.

The Google Cloud OAuth callback remains the Supabase callback URL shown on the Google provider page. The web app builds its post-auth redirect from `window.location.origin`, so each Vercel preview returns to itself.

Account deletion requires a Supabase session created within the preceding ten minutes. When the current session is older, the web app emails a fresh magic sign-in link before exposing the deletion action. The Edge Function deletes the Auth user with the service role and relies on existing foreign-key cascades for profile, attempts, and personal-best cleanup.

With Docker running, verify the local database:

```sh
supabase start
supabase db reset
supabase test db
```

## Deploy to Vercel

Import this repository and use:

- Root Directory: `apps/web`
- Framework Preset: Vite
- Build Command: `npm run build`
- Output Directory: `dist`
- Include source files outside the Root Directory: enabled

Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` separately for Production and Preview. `apps/web/vercel.json` provides React Router SPA rewrites and same-origin permissions for motion, camera, and microphone.

Enable Web Analytics for the Vercel project before deploying. The app mounts the official `@vercel/analytics` React component at its root, so page loads and client-side route changes are reported after deployment without adding a cookie banner.

Deployment references: [Vite on Vercel](https://vercel.com/docs/frameworks/frontend/vite), [Vercel monorepos](https://vercel.com/docs/monorepos/monorepo-faq), [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls), and [Supabase Edge Function deployment](https://supabase.com/docs/guides/functions/quickstart).

## Verify the preserved iOS app

```sh
cd apps/ios
xcodebuild -project YEET.xcodeproj \
  -scheme YEET \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

The migration baseline and the relocated project both pass 41 native tests. Swift configuration now lives under `apps/ios/YEET/Configuration/`.

## Physical acceptance before public launch

Test each supported browser/device family before public launch:

- Multiple iPhone generations on iOS 18 and the current iOS, using Safari.
- Current Pixel and Samsung models using Chrome.
- Twenty controlled tosses and ten invalid/no-throw cases per device.
- Median airtime error at most 50ms and no error over 100ms against 240fps video.
- Twenty consecutive complete POV recordings with audio, replay, branded export, and share/download.

Rankings are casual/social, not hardware-attested or prize-grade. POV recordings are temporary object URLs and never leave the device unless the player explicitly shares or downloads one.

The first-run safety acknowledgment and legal notices reduce ambiguity but are not a substitute for Washington legal advice, appropriate insurance, or a separate business entity. Support-email forwarding and Resend reply setup are documented in [`ENVIRONMENT.md`](ENVIRONMENT.md).
