import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "../lib/supabase";

export function AuthCallback() {
  const navigate = useNavigate();
  const [message, setMessage] = useState("FINISHING SIGN-IN…");
  useEffect(() => {
    const client = supabase;
    if (!client) { setMessage("SIGN-IN IS NOT CONFIGURED"); return; }
    const finish = async () => {
      const { data: existing } = await client.auth.getSession();
      if (!existing.session) {
        const code = new URLSearchParams(window.location.search).get("code");
        if (!code) { setMessage("SIGN-IN LINK IS INVALID"); return; }
        const { error } = await client.auth.exchangeCodeForSession(code);
        if (error) { setMessage(error.message.toUpperCase()); return; }
      }
      window.setTimeout(() => navigate("/", { replace: true }), 350);
    };
    void finish();
  }, [navigate]);
  return <main className="state-screen yellow-screen"><div className="spinner-mark">Y</div><h1>{message}</h1><p>You can close this page if you opened YEET somewhere else.</p></main>;
}
