# YEET

YEET measures iPhone airtime with Core Motion, optionally records a temporary rear-camera POV, and uses Supabase for native Sign in with Apple, public handles, personal-best score saving, and the embedded global leaderboard. Guests can always toss without an account.

## Finish the Supabase setup

The local app configuration has already been created for this checkout and is ignored by Git. Only the project reference and publishable key belong in `YEET/Configuration/Config.local.xcconfig`. Never put a database password, connection string, secret key, service-role key, or Apple `.p8` contents in the app.

### 1. Create the database objects

1. Open the YEET project in the Supabase Dashboard.
2. Open **SQL Editor**, create a new query, and run `supabase/migrations/20260826000100_accounts_and_leaderboard.sql` followed by `supabase/migrations/20260826000200_unbounded_airtime_and_six_leaders.sql` in filename order.
3. The migrations create `profiles`, `attempts`, `personal_bests`, the three client RPCs, indexes, RLS, and restricted grants, then remove the former three-second score ceiling and expand leaderboard snapshots to six leaders. They do not create fake scores. Deploy both migrations before distributing this client.
4. In **Database → Tables**, confirm all three tables show RLS enabled.
5. In **Database → Functions**, confirm `leaderboard_snapshot`, `set_profile_handle`, and `submit_attempt` exist.

Leaderboard order is highest airtime first. If two personal bests have the same airtime, the earlier `achieved_at` wins and receives the earlier rank. A new guest candidate ranks behind every existing equal score.

### 2. Configure native Sign in with Apple

1. In Apple Developer, open the App ID for `com.dpl8300.yeet`, enable **Sign in with Apple**, and save it.
2. In Supabase, open **Authentication → Providers → Apple**, enable the provider, and add `com.dpl8300.yeet` as a Client ID. If you also created a web Services ID, list that Services ID first and the bundle ID as an additional Client ID.
3. The app uses native token sign-in, so it does not need a Services ID or OAuth redirect to sign users in. If a web/Services ID is also configured, its Apple Return URL is `https://mthczujfiegzvqrgovpy.supabase.co/auth/v1/callback`; that URL is not embedded in the iOS app.
4. Xcode is already configured with the matching Sign in with Apple entitlement. After changing the App ID, allow the automatic provisioning profile to refresh before running on a device.

### 3. Deploy account deletion

Install the Supabase CLI and link this checkout:

```sh
brew install supabase/tap/supabase
supabase login
supabase link --project-ref mthczujfiegzvqrgovpy
supabase functions deploy delete-account
```

Then create a **Sign in with Apple key** in Apple Developer and download its `.p8` file. Apple only provides that file once, so store it in a password manager or another secure location outside this repository.

In **Supabase → Project Settings → Edge Functions → Secrets**, add:

- `APPLE_TEAM_ID`: `TSKRB6UAPL`
- `APPLE_KEY_ID`: the Key ID shown by Apple
- `APPLE_CLIENT_ID`: `com.dpl8300.yeet`
- `APPLE_PRIVATE_KEY_BASE64`: a one-line base64 encoding of the entire `.p8` file

On macOS, create the base64 value with the command below, replacing the path with the private file’s real location. Paste the output directly into the Supabase secret field; do not paste it into source code or chat.

```sh
base64 -i /secure/path/AuthKey_KEYID.p8 | tr -d '\n'
```

Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to the deployed function automatically. Confirm **Edge Functions** lists `delete-account`. Account deletion deliberately requires a fresh Apple confirmation, revokes the new Apple authorization, deletes the Auth user server-side, and relies on foreign-key cascades to remove the player and scores.

### 4. Verify the backend locally (optional but recommended)

With Docker running:

```sh
supabase start
supabase db reset
supabase test db
```

The pgTAP suite in `supabase/tests/database/leaderboard.test.sql` checks public reads, denied direct writes, authentication requirements, minimum detector bounds, scores above three seconds, six ordered leaders, rate limiting, idempotency, personal-best replacement, deterministic ties, and deletion cascades.

## Run on an iPhone

1. Open `YEET.xcodeproj` in Xcode 26.6 or newer and let Swift Package Manager resolve Supabase 2.x.
2. In the YEET target’s **Signing & Capabilities** pane, select team `TSKRB6UAPL` and confirm **Sign in with Apple** appears.
3. Connect an iPhone running iOS 18 or newer, enable Developer Mode, select it as the run destination, and run the `YEET` scheme.
4. Verify that the first-launch tutorial appears once and remains available from the account sheet. Confirm the fixed home dashboard shows three leaders on a short device and six on a roomy device without scrolling.
5. Verify that the public leaderboard loads while signed out, then sign in, choose a handle, and complete a valid toss. The result should save once and update PB/rank.
6. Test persistent POV selection, replay, branded-video export, Save to Photos, sharing, handle editing, sign-out, retry after temporarily disabling networking, and confirmed account deletion.

The simulator is useful for UI, networking, and synthetic tests, but it cannot validate live freefall detection, physical haptics, native Apple credentials, or POV capture as completely as a signed physical device.

## Verify the iOS code

```sh
xcodebuild -project YEET.xcodeproj \
  -scheme YEET \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Initial detector values live in `DetectionConfig.spikeV1`. Airtime uses the first confirmed low-g sample and first confirmed landing-exit sample’s Core Motion timestamps; confirmation latency is not added to the result. Production has no maximum airtime ceiling: confirmed landing, sensor failures or gaps, app inactivity, and the pre-throw timeout remain the terminal safeguards.

## Calibrate

DEBUG builds show a throttled sensor panel. State changes and threshold crossings use unified logging. When a detector session finishes or is rejected, the Xcode console prints a `YEET_TRACE_BEGIN`/`YEET_TRACE_END` CSV block containing the full in-memory sensor trace. Use that trace to tune one category of values at a time, then replay representative sequences through the unit tests.

## Prototype boundary

Basic server checks reduce casual score abuse, but they cannot prove that motion data is genuine. Handles currently have no profanity filtering, reporting, blocking, moderation tooling, or support contact flow. The leaderboard is therefore a prototype and is not ready for public App Store submission under Apple’s user-generated-content requirements.
