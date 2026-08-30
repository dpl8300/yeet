import { useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { LogOut, Mail, ShieldAlert } from "lucide-react";
import {
  deleteAccount,
  isSupabaseConfigured,
  sendEmailMagicLink,
  setHandle,
  signInWithGoogle,
  type LeaderboardEntry
} from "../lib/backend";
import { isValidHandle, normalizeHandle } from "../lib/utils";
import { supabase } from "../lib/supabase";
import {
  classifyAnalyticsError,
  trackEvent,
  type AccountSource
} from "../lib/analytics";
import { Button } from "./ui/Button";
import { Dialog } from "./ui/Dialog";
import { Input } from "./ui/Input";

export function AccountDialog({ open, onOpenChange, session, profile, source, onChanged }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  session: Session | null;
  profile?: LeaderboardEntry | null;
  source: AccountSource;
  onChanged: () => void;
}) {
  const [email, setEmail] = useState(session?.user.email ?? "");
  const [handle, setHandleValue] = useState(profile?.handle ?? "");
  const [deleting, setDeleting] = useState(false);
  const [message, setMessage] = useState<string>();
  const [busy, setBusy] = useState(false);
  const freshSession = hasFreshSignIn(session);

  const run = async (
    action: () => Promise<void>,
    success?: string,
    onSuccess?: () => void,
    onFailure?: (error: unknown) => void
  ) => {
    setBusy(true); setMessage(undefined);
    try { await action(); if (success) setMessage(success); onSuccess?.(); onChanged(); }
    catch (error) { onFailure?.(error); setMessage(error instanceof Error ? error.message : "Something went wrong."); }
    finally { setBusy(false); }
  };

  const authFailure = (method: "google" | "email") => (error: unknown) => {
    trackEvent("auth_failed", { method, reason: classifyAnalyticsError(error) });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange} title={session ? "YOUR ACCOUNT" : "SAVE YOUR SCORES"} description={session ? session.user.email ?? "Signed in" : "Guest play is always available. Sign in only when you want a saved score."}>
      {!isSupabaseConfigured && <p className="status-message warning">Accounts will be available after the two Vite Supabase environment variables are added.</p>}
      {!session ? (
        <div className="dialog-stack">
          <Button disabled={busy || !isSupabaseConfigured} onClick={() => {
            trackEvent("auth_started", { method: "google", source });
            void run(signInWithGoogle, undefined, undefined, authFailure("google"));
          }} className="google-button"><span className="google-g">G</span>CONTINUE WITH GOOGLE</Button>
          <div className="or-line"><span>OR</span></div>
          <label className="field-label">EMAIL<Input autoComplete="email" inputMode="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" /></label>
          <Button disabled={busy || !email || !isSupabaseConfigured} onClick={() => {
            trackEvent("auth_started", { method: "email", source });
            void run(
              async () => { await sendEmailMagicLink(email); },
              "Check your email for your sign-in link.",
              () => trackEvent("auth_link_sent", { purpose: "sign_in", source }),
              authFailure("email")
            );
          }}><Mail /> EMAIL ME A MAGIC LINK</Button>
        </div>
      ) : (
        <div className="dialog-stack">
          <label className="field-label">HANDLE<Input value={handle} onChange={(event) => setHandleValue(event.target.value)} placeholder="your_handle" /></label>
          <p className="field-help">3–20 lowercase letters, numbers, or underscores.</p>
          <Button disabled={busy || !isValidHandle(handle)} onClick={() => {
            const action = profile ? "update" : "create";
            void run(
              async () => { await setHandle(normalizeHandle(handle)); },
              "Handle saved.",
              () => trackEvent("profile_save_result", { action, outcome: "success" }),
              (error) => trackEvent("profile_save_result", { action, outcome: classifyAnalyticsError(error) })
            );
          }}>{profile ? "UPDATE HANDLE" : "CREATE HANDLE"}</Button>
          <Button variant="secondary" disabled={busy} onClick={() => void run(async () => {
            await supabase?.auth.signOut({ scope: "local" });
            trackEvent("signed_out");
            onOpenChange(false);
          })}><LogOut /> SIGN OUT</Button>
          <button className="danger-link" onClick={() => {
            trackEvent("account_delete_prompted", { fresh_session: freshSession });
            setDeleting(true);
          }}><ShieldAlert /> Delete account</button>
          {deleting && (
            <div className="danger-zone">
              <b>{freshSession ? "PERMANENTLY DELETE ACCOUNT?" : "FRESH SIGN-IN REQUIRED"}</b>
              <p>{freshSession
                ? "This permanently deletes your auth user, profile, attempts, and personal best."
                : "We’ll email a magic link to refresh your session. Open it, then return here to delete your account."}</p>
              {freshSession ? (
                <Button disabled={busy} onClick={() => void run(
                  async () => { await deleteAccount(); onOpenChange(false); },
                  undefined,
                  () => trackEvent("account_delete_result", { outcome: "success", reason: "none" }),
                  (error) => trackEvent("account_delete_result", { outcome: "failure", reason: classifyAnalyticsError(error) })
                )}>DELETE MY ACCOUNT</Button>
              ) : (
                <Button variant="secondary" disabled={busy || !session.user.email} onClick={() => {
                  trackEvent("auth_started", { method: "email", source });
                  void run(
                    async () => { await sendEmailMagicLink(session.user.email!); },
                    "Check your email for your fresh sign-in link.",
                    () => {
                      trackEvent("auth_link_sent", { purpose: "delete_reauth", source });
                      trackEvent("account_delete_result", { outcome: "reauth_sent", reason: "none" });
                    },
                    (error) => {
                      authFailure("email")(error);
                      trackEvent("account_delete_result", { outcome: "failure", reason: classifyAnalyticsError(error) });
                    }
                  );
                }}>EMAIL VERIFICATION LINK</Button>
              )}
            </div>
          )}
        </div>
      )}
      {message && <p className="status-message" role="status">{message}</p>}
    </Dialog>
  );
}

function hasFreshSignIn(session: Session | null) {
  const signedInAt = session?.user.last_sign_in_at;
  if (!signedInAt) return false;
  const age = Date.now() - Date.parse(signedInAt);
  return age >= 0 && age < 9 * 60 * 1_000;
}
