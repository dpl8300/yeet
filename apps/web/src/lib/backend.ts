import type { RawTraceSample } from "@yeet/airtime-core";
import { isSupabaseConfigured, supabase } from "./supabase";
import { normalizeHandle } from "./utils";

export type LeaderboardEntry = {
  user_id: string;
  handle: string;
  rank: number | null;
  airtime_ms: number | null;
  achieved_at: string | null;
};

export type LeaderboardSnapshot = {
  leaders: LeaderboardEntry[];
  current_user: LeaderboardEntry | null;
  candidate_rank: number | null;
  total_players: number;
};

export type ScoreSubmission = {
  attempt_id: string;
  personal_best_ms: number;
  rank: number;
  is_personal_best: boolean;
  already_processed: boolean;
};

const cacheKey = "yeet.leaderboard.v1";
export const emptySnapshot: LeaderboardSnapshot = { leaders: [], current_user: null, candidate_rank: null, total_players: 0 };

export function cachedLeaderboard() {
  try {
    const raw = localStorage.getItem(cacheKey);
    return raw ? JSON.parse(raw) as LeaderboardSnapshot : undefined;
  } catch { return undefined; }
}

export async function getLeaderboard(candidateMs?: number): Promise<LeaderboardSnapshot> {
  if (!supabase) throw new Error("Leaderboard unavailable until Supabase is configured.");
  const { data, error } = await supabase.rpc("leaderboard_snapshot", { p_candidate_airtime_ms: candidateMs ?? null });
  if (error) throw error;
  const snapshot = data as LeaderboardSnapshot;
  if (candidateMs == null) localStorage.setItem(cacheKey, JSON.stringify(snapshot));
  return snapshot;
}

export async function setHandle(handle: string) {
  if (!supabase) throw new Error("Accounts are not configured.");
  const { data, error } = await supabase.rpc("set_profile_handle", { p_handle: normalizeHandle(handle) });
  if (error) throw error;
  return data as { id: string; handle: string };
}

export async function submitAttempt(attemptId: string, samples: RawTraceSample[]) {
  if (!supabase) throw new Error("Score saving is unavailable.");
  const { data, error } = await supabase.functions.invoke("submit-attempt", {
    body: { attempt_id: attemptId, samples }
  });
  if (error) throw error;
  return data as ScoreSubmission;
}

export async function signInWithGoogle() {
  if (!supabase) throw new Error("Accounts are not configured.");
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: `${window.location.origin}/auth/callback`, skipBrowserRedirect: false }
  });
  if (error) throw error;
}

export async function sendEmailOtp(email: string) {
  if (!supabase) throw new Error("Accounts are not configured.");
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: true, emailRedirectTo: `${window.location.origin}/auth/callback` }
  });
  if (error) throw error;
}

export async function verifyEmailOtp(email: string, token: string) {
  if (!supabase) throw new Error("Accounts are not configured.");
  const { error } = await supabase.auth.verifyOtp({ email, token, type: "email" });
  if (error) throw error;
}

export async function deleteAccount() {
  if (!supabase) throw new Error("Accounts are not configured.");
  const { error } = await supabase.functions.invoke("delete-account", { body: {} });
  if (error) throw error;
  await supabase.auth.signOut({ scope: "local" });
}

export { isSupabaseConfigured };
