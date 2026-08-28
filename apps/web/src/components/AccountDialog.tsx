import { useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { LogOut, Mail, ShieldAlert } from "lucide-react";
import {
  deleteAccount,
  isSupabaseConfigured,
  sendEmailOtp,
  setHandle,
  signInWithGoogle,
  verifyEmailOtp,
  type LeaderboardEntry
} from "../lib/backend";
import { isValidHandle, normalizeHandle } from "../lib/utils";
import { supabase } from "../lib/supabase";
import { Button } from "./ui/Button";
import { Dialog } from "./ui/Dialog";
import { Input } from "./ui/Input";

export function AccountDialog({ open, onOpenChange, session, profile, onChanged }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  session: Session | null;
  profile?: LeaderboardEntry | null;
  onChanged: () => void;
}) {
  const [email, setEmail] = useState(session?.user.email ?? "");
  const [token, setToken] = useState("");
  const [handle, setHandleValue] = useState(profile?.handle ?? "");
  const [step, setStep] = useState<"email" | "otp">("email");
  const [deleting, setDeleting] = useState(false);
  const [message, setMessage] = useState<string>();
  const [busy, setBusy] = useState(false);

  const run = async (action: () => Promise<void>, success?: string) => {
    setBusy(true); setMessage(undefined);
    try { await action(); if (success) setMessage(success); onChanged(); }
    catch (error) { setMessage(error instanceof Error ? error.message : "Something went wrong."); }
    finally { setBusy(false); }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange} title={session ? "YOUR ACCOUNT" : "SAVE YOUR SCORES"} description={session ? session.user.email ?? "Signed in" : "Guest play is always available. Sign in only when you want a saved score."}>
      {!isSupabaseConfigured && <p className="status-message warning">Accounts will be available after the two Vite Supabase environment variables are added.</p>}
      {!session ? (
        <div className="dialog-stack">
          <Button disabled={busy || !isSupabaseConfigured} onClick={() => run(signInWithGoogle)} className="google-button"><span className="google-g">G</span>CONTINUE WITH GOOGLE</Button>
          <div className="or-line"><span>OR</span></div>
          <label className="field-label">EMAIL<Input autoComplete="email" inputMode="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" /></label>
          {step === "otp" && <label className="field-label">SIX-DIGIT CODE<Input autoComplete="one-time-code" inputMode="numeric" maxLength={6} value={token} onChange={(event) => setToken(event.target.value.replace(/\D/g, ""))} placeholder="000000" /></label>}
          {step === "email" ? (
            <Button disabled={busy || !email || !isSupabaseConfigured} onClick={() => run(async () => { await sendEmailOtp(email); setStep("otp"); }, "Check your email for a six-digit code.")}><Mail /> EMAIL ME A CODE</Button>
          ) : (
            <Button disabled={busy || token.length !== 6} onClick={() => run(async () => { await verifyEmailOtp(email, token); onOpenChange(false); })}>VERIFY & SIGN IN</Button>
          )}
        </div>
      ) : (
        <div className="dialog-stack">
          <label className="field-label">HANDLE<Input value={handle} onChange={(event) => setHandleValue(event.target.value)} placeholder="your_handle" /></label>
          <p className="field-help">3–20 lowercase letters, numbers, or underscores.</p>
          <Button disabled={busy || !isValidHandle(handle)} onClick={() => run(async () => { await setHandle(normalizeHandle(handle)); }, "Handle saved.")}>{profile ? "UPDATE HANDLE" : "CREATE HANDLE"}</Button>
          <Button variant="secondary" disabled={busy} onClick={() => run(async () => { await supabase?.auth.signOut({ scope: "local" }); onOpenChange(false); })}><LogOut /> SIGN OUT</Button>
          <button className="danger-link" onClick={() => { setDeleting(true); setStep("email"); setToken(""); }}><ShieldAlert /> Delete account</button>
          {deleting && (
            <div className="danger-zone">
              <b>FRESH EMAIL VERIFICATION REQUIRED</b>
              <p>We create a new verified session before permanently deleting your auth user, profile, attempts, and personal best.</p>
              {step === "email" ? (
                <Button variant="secondary" disabled={busy || !email} onClick={() => run(async () => { await sendEmailOtp(email); setStep("otp"); }, "Enter the code we sent.")}>SEND DELETION CODE</Button>
              ) : (
                <>
                  <Input aria-label="Deletion verification code" inputMode="numeric" maxLength={6} value={token} onChange={(event) => setToken(event.target.value.replace(/\D/g, ""))} placeholder="000000" />
                  <Button disabled={busy || token.length !== 6} onClick={() => run(async () => { await verifyEmailOtp(email, token); await deleteAccount(); onOpenChange(false); })}>DELETE MY ACCOUNT</Button>
                </>
              )}
            </div>
          )}
        </div>
      )}
      {message && <p className="status-message" role="status">{message}</p>}
    </Dialog>
  );
}
