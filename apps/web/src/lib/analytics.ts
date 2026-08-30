import { track } from "@vercel/analytics";

export type AccountState =
  | "guest"
  | "signed_in_no_handle"
  | "signed_in_no_score"
  | "signed_in_scored"
  | "signed_in_unknown";

export type AccountSource = "home" | "settings" | "result" | "game";
export type AuthMethod = "google" | "email" | "unknown";
export type AnalyticsErrorReason =
  | "not_configured"
  | "missing_code"
  | "motion_unsupported"
  | "permission_denied"
  | "preflight_unreliable"
  | "preflight_uncalibrated"
  | "page_hidden"
  | "timeout"
  | "no_throw"
  | "too_short"
  | "sample_gap"
  | "invalid_timestamp"
  | "invalid_sample"
  | "profile_required"
  | "authentication_required"
  | "rate_limited"
  | "handle_taken"
  | "invalid_handle"
  | "validation_failed"
  | "network"
  | "unknown";

type AnalyticsEvents = {
  legal_gate_viewed: { reason: "first_visit" | "version_update"; version: string };
  legal_accepted: { prior_status: "missing" | "outdated"; version: string };
  tutorial_replay_viewed: { account_state: AccountState };
  tutorial_replay_completed: { account_state: AccountState };
  home_viewed: { account_state: AccountState; display_mode: "browser" | "standalone" };
  settings_opened: { account_state: AccountState; display_mode: "browser" | "standalone" };
  leaderboard_opened: { account_state: AccountState; data_state: "live" | "loading" | "cached" | "error" | "unconfigured" };
  pwa_installed: undefined;
  account_opened: { account_state: AccountState; source: AccountSource };
  auth_started: { method: Exclude<AuthMethod, "unknown">; source: AccountSource };
  auth_link_sent: { purpose: "sign_in" | "delete_reauth"; source: AccountSource };
  auth_succeeded: { method: AuthMethod; callback_state: "code_exchange" | "existing_session" };
  auth_failed: { method: AuthMethod; reason: AnalyticsErrorReason };
  profile_save_result: { action: "create" | "update"; outcome: "success" | AnalyticsErrorReason };
  signed_out: undefined;
  account_delete_prompted: { fresh_session: boolean };
  account_delete_result: { outcome: "success" | "failure" | "reauth_sent"; reason: AnalyticsErrorReason | "none" };
  pov_setting_changed: { outcome: "enabled" | "disabled" | "unsupported"; display_mode: "browser" | "standalone" };
  yeet_started: { account_state: AccountState; pov_requested: boolean };
  yeet_ready: { account_state: AccountState; pov_active: boolean };
  throw_detected: { account_state: AccountState; pov_active: boolean };
  yeet_completed: { account_state: AccountState; airtime_bucket: ReturnType<typeof airtimeBucket> };
  yeet_invalid: { account_state: AccountState; reason: AnalyticsErrorReason };
  result_action: { account_state: AccountState; action: "yeet_again" | "back_home" | "open_account" | "open_pov" | "retry_save" | "retry_invalid" };
  guest_rank_result: { outcome: "success" | "failure" | "unavailable"; rank_bucket: ReturnType<typeof rankBucket> };
  score_save_result: { outcome: "first_score" | "personal_best" | "saved" | "duplicate" | "failure"; detail: ReturnType<typeof rankBucket> | AnalyticsErrorReason };
  achievement_viewed: { kind: "first_rank" | "personal_best" | "world_record"; rank_bucket: ReturnType<typeof rankBucket> };
  pov_recording_result: { outcome: "available" | "prepare_failed" | "start_failed" | "finalize_failed"; account_state: AccountState };
  pov_viewed: { account_state: AccountState; result_kind: "normal" | "personal_best" | "world_record" };
  pov_closed: { account_state: AccountState; stage: "replay" | "exporting" | "share" | "failed" };
  pov_playback_started: { account_state: AccountState; stage: "replay" };
  pov_playback_completed: { account_state: AccountState; stage: "replay" };
  pov_export_started: { account_state: AccountState; format: "branded" | "raw" };
  pov_export_result: { outcome: "success" | "failure" | "cancelled"; format: "branded" | "raw" };
  pov_share_result: { outcome: "shared" | "downloaded" | "cancelled" | "failure"; format: "branded" | "raw" };
};

type TrackArgs<Name extends keyof AnalyticsEvents> = AnalyticsEvents[Name] extends undefined
  ? []
  : [properties: AnalyticsEvents[Name]];

export function trackEvent<Name extends keyof AnalyticsEvents>(name: Name, ...args: TrackArgs<Name>) {
  const properties = args[0] as Record<string, string | number | boolean | null> | undefined;
  if (properties && Object.keys(properties).length > 2) {
    if (import.meta.env.DEV) console.warn(`Analytics event ${name} exceeds Vercel Pro's two-property limit.`);
    return;
  }
  try {
    track(name, properties);
  } catch {
    // Analytics must never interrupt gameplay, authentication, or account management.
  }
}

export function accountState(
  session: { user: unknown } | null,
  profile: { airtime_ms: number | null } | null | undefined,
  profileResolved = true
): AccountState {
  if (!session) return "guest";
  if (!profileResolved) return "signed_in_unknown";
  if (!profile) return "signed_in_no_handle";
  return profile.airtime_ms == null ? "signed_in_no_score" : "signed_in_scored";
}

export function displayMode(): "browser" | "standalone" {
  const navigatorWithStandalone = navigator as Navigator & { standalone?: boolean };
  return window.matchMedia?.("(display-mode: standalone)").matches || navigatorWithStandalone.standalone
    ? "standalone"
    : "browser";
}

export function airtimeBucket(milliseconds: number) {
  if (milliseconds < 250) return "under_0_25s" as const;
  if (milliseconds < 500) return "0_25_0_49s" as const;
  if (milliseconds < 750) return "0_50_0_74s" as const;
  if (milliseconds < 1_000) return "0_75_0_99s" as const;
  if (milliseconds < 1_500) return "1_00_1_49s" as const;
  return "1_50s_plus" as const;
}

export function rankBucket(rank?: number | null) {
  if (rank == null || !Number.isFinite(rank)) return "none" as const;
  if (rank === 1) return "rank_1" as const;
  if (rank <= 10) return "rank_2_10" as const;
  if (rank <= 100) return "rank_11_100" as const;
  if (rank <= 1_000) return "rank_101_1000" as const;
  return "rank_1001_plus" as const;
}

export function classifyAnalyticsError(error: unknown, fallback: AnalyticsErrorReason = "unknown"): AnalyticsErrorReason {
  const message = error instanceof Error ? `${error.name} ${error.message}`.toLowerCase() : "";
  if (message.includes("not configured") || message.includes("unavailable until")) return "not_configured";
  if (message.includes("profile_required")) return "profile_required";
  if (message.includes("authentication_required") || message.includes("jwt")) return "authentication_required";
  if (message.includes("rate_limit") || message.includes("rate limit") || message.includes("too many")) return "rate_limited";
  if (message.includes("handle_taken") || message.includes("duplicate") || message.includes("unique")) return "handle_taken";
  if (message.includes("invalid_handle")) return "invalid_handle";
  if (message.includes("invalid_attempt") || message.includes("validation") || message.includes("trace")) return "validation_failed";
  if (message.includes("network") || message.includes("fetch") || message.includes("timeout") || message.includes("failed to load")) return "network";
  return fallback;
}

export function authMethod(session: { user: { app_metadata?: { provider?: unknown } } } | null): AuthMethod {
  const provider = session?.user.app_metadata?.provider;
  if (provider === "google") return "google";
  if (provider === "email") return "email";
  return "unknown";
}

export function redactAnalyticsUrl<Event extends { url: string }>(event: Event): Event {
  try {
    const url = new URL(event.url, window.location.origin);
    url.search = "";
    url.hash = "";
    return { ...event, url: url.toString() };
  } catch {
    return { ...event, url: event.url.split(/[?#]/, 1)[0] };
  }
}
