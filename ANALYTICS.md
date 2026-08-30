# YEET analytics

YEET uses Vercel Web Analytics page views and custom events. Analytics is intentionally anonymous: the app does not create an analytics ID and never sends a Supabase user ID, email, handle, attempt ID, raw motion trace, POV data, authentication code, or unfiltered error message to Vercel. Query strings and URL fragments are removed in `beforeSend`.

## Event catalog

Every custom event has at most two low-cardinality properties so it fits the base Vercel Pro limit.

| Event | Properties | Meaning |
| --- | --- | --- |
| `legal_gate_viewed` | `reason`, `version` | First-time or updated-terms gate displayed. |
| `legal_accepted` | `prior_status`, `version` | Current Terms accepted and Privacy Notice acknowledged. |
| `tutorial_replay_viewed` / `tutorial_replay_completed` | `account_state` | Optional safety tutorial replay funnel. |
| `home_viewed` | `account_state`, `display_mode` | Home became usable after session/profile state resolved. |
| `settings_opened` | `account_state`, `display_mode` | Settings opened. |
| `leaderboard_opened` | `account_state`, `data_state` | Full leaderboard opened and whether its data was live, loading, cached, unavailable, or errored. |
| `pwa_installed` | — | Browser reported successful app installation. |
| `account_opened` | `account_state`, `source` | Account dialog opened from home, settings, a result, or gameplay. |
| `auth_started` | `method`, `source` | Google or email sign-in action began. |
| `auth_link_sent` | `purpose`, `source` | Email link sent for sign-in or deletion reauthentication. |
| `auth_succeeded` | `method`, `callback_state` | Auth callback completed through code exchange or an existing callback session. |
| `auth_failed` | `method`, `reason` | Auth initiation or callback failed with an allowlisted category. |
| `profile_save_result` | `action`, `outcome` | Handle creation/update succeeded or failed. |
| `signed_out` | — | Local sign-out completed. |
| `account_delete_prompted` | `fresh_session` | Delete-account disclosure opened. |
| `account_delete_result` | `outcome`, `reason` | Deletion succeeded/failed or a reauthentication link was sent. |
| `pov_setting_changed` | `outcome`, `display_mode` | POV was enabled, disabled, or rejected as unsupported. |
| `yeet_started` | `account_state`, `pov_requested` | Player pressed YEET and device preparation began. |
| `yeet_ready` | `account_state`, `pov_active` | Permissions, preflight, and countdown completed. |
| `throw_detected` | `account_state`, `pov_active` | Detector first entered an airborne/possible-landing state. |
| `yeet_completed` | `account_state`, `airtime_bucket` | A valid catch completed. |
| `yeet_invalid` | `account_state`, `reason` | Preparation or detection ended with a fixed failure category. |
| `result_action` | `account_state`, `action` | Retry, home, account, POV, or score-retry action selected from a result state. |
| `guest_rank_result` | `outcome`, `rank_bucket` | Guest estimate succeeded, failed, or was unavailable. |
| `score_save_result` | `outcome`, `detail` | Signed-in score save result and coarse rank or failure category. |
| `achievement_viewed` | `kind`, `rank_bucket` | First rank, personal best, or world-record celebration shown. |
| `pov_recording_result` | `outcome`, `account_state` | POV became available or failed during prepare, start, or finalization. |
| `pov_viewed` / `pov_closed` | `account_state`, `result_kind` or `stage` | POV dialog entry and exit. |
| `pov_playback_started` / `pov_playback_completed` | `account_state`, `stage` | First raw playback start/completion in an opening. |
| `pov_export_started` | `account_state`, `format` | Branded or raw share preparation began. |
| `pov_export_result` | `outcome`, `format` | Export succeeded, failed, or was cancelled. |
| `pov_share_result` | `outcome`, `format` | Native share, download fallback, cancellation, or failure. |

## Property values

- `account_state`: `guest`, `signed_in_no_handle`, `signed_in_no_score`, `signed_in_scored`, or `signed_in_unknown` when profile state could not be resolved.
- `airtime_bucket`: `under_0_25s`, `0_25_0_49s`, `0_50_0_74s`, `0_75_0_99s`, `1_00_1_49s`, or `1_50s_plus`.
- `rank_bucket`: `rank_1`, `rank_2_10`, `rank_11_100`, `rank_101_1000`, `rank_1001_plus`, or `none`.
- Failures use fixed categories such as `motion_unsupported`, `permission_denied`, `preflight_unreliable`, `preflight_uncalibrated`, `page_hidden`, `timeout`, `no_throw`, `too_short`, `sample_gap`, `invalid_timestamp`, `invalid_sample`, `profile_required`, `authentication_required`, `rate_limited`, `handle_taken`, `invalid_handle`, `validation_failed`, `network`, and `unknown`.

## Dashboard recipes

Use **Vercel project → Analytics → Events**, select Production, and apply the event/property filters below.

- Legal acceptance: compare `legal_gate_viewed` with `legal_accepted`, split by `reason` or `prior_status`. This is gate abandonment, not a timed exit signal.
- Guest play: filter `yeet_started`, `throw_detected`, or `yeet_completed` to `account_state=guest`. Compare the three counts for preparation and detection drop-off.
- Signed-in visitors without a saved YEET: inspect `home_viewed` with `account_state=signed_in_no_handle` and `signed_in_no_score`. These are anonymous daily visitors, not durable account cohorts.
- Full play funnel: compare `yeet_started` → `yeet_ready` → `throw_detected` → `yeet_completed`, then inspect `yeet_invalid.reason` for losses.
- Authentication: compare `account_opened` → `auth_started` → `auth_link_sent` where applicable → `auth_succeeded`; inspect `auth_failed.reason`.
- Ranked conversion: compare signed-in `yeet_completed` with `score_save_result`; split successful saves by `outcome` and rank bucket.
- POV adoption: compare `pov_setting_changed`, `pov_recording_result`, `pov_viewed`, `pov_export_started`, `pov_export_result`, and `pov_share_result`.

Vercel's built-in bounce rate is based on page-view sessions; custom events do not count as navigation or change that metric. Since YEET gameplay stays on `/`, built-in bounce should not be interpreted as “left before accepting the Terms.”

## Cost and retention

Page views and custom events are billable Web Analytics events. The implementation is unsampled and deliberately emits only meaningful transitions. Base Vercel Pro currently supports two properties per custom event and a 12-month reporting window; review current pricing and configure Spend Management in Vercel before high-volume promotion.
