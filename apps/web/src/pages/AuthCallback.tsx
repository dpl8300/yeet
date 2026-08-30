import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "../lib/supabase";
import { authMethod, classifyAnalyticsError, trackEvent } from "../lib/analytics";

export function AuthCallback() {
  const navigate = useNavigate();
  const [message, setMessage] = useState("FINISHING SIGN-IN…");
  const started = useRef(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    const client = supabase;
    if (!client) {
      setMessage("SIGN-IN IS NOT CONFIGURED");
      trackEvent("auth_failed", { method: "unknown", reason: "not_configured" });
      return;
    }
    const finish = async () => {
      const { data: existing, error: sessionError } = await client.auth.getSession();
      if (sessionError) {
        setMessage(sessionError.message.toUpperCase());
        trackEvent("auth_failed", { method: "unknown", reason: classifyAnalyticsError(sessionError) });
        return;
      }
      if (!existing.session) {
        const code = new URLSearchParams(window.location.search).get("code");
        if (!code) {
          setMessage("SIGN-IN LINK IS INVALID");
          trackEvent("auth_failed", { method: "unknown", reason: "missing_code" });
          return;
        }
        const { data, error } = await client.auth.exchangeCodeForSession(code);
        if (error) {
          setMessage(error.message.toUpperCase());
          trackEvent("auth_failed", { method: "unknown", reason: classifyAnalyticsError(error) });
          return;
        }
        trackEvent("auth_succeeded", { method: authMethod(data.session), callback_state: "code_exchange" });
      } else {
        trackEvent("auth_succeeded", { method: authMethod(existing.session), callback_state: "existing_session" });
      }
      window.setTimeout(() => navigate("/", { replace: true }), 350);
    };
    void finish();
  }, [navigate]);
  return <main className="state-screen yellow-screen"><div className="spinner-mark">Y</div><h1>{message}</h1><p>You can close this page if you opened YEET somewhere else.</p></main>;
}
