import { Link } from "react-router-dom";

export function LegalPage({ type }: { type: "privacy" | "terms" }) {
  return (
    <main className="legal-shell">
      <article className="legal-card">
        <Link to="/" className="back-link">← BACK TO YEET</Link>
        <p className="eyebrow">YEET · AUGUST 28, 2026</p>
        <h1>{type === "privacy" ? "PRIVACY" : "TERMS"}</h1>
        {type === "privacy" ? <Privacy /> : <Terms />}
      </article>
    </main>
  );
}

function Privacy() {
  return <>
    <h2>THE SHORT VERSION</h2><p>Motion traces and POV recordings are processed on your device. Raw motion traces are sent only for signed-in ranked submissions, validated by our Supabase Edge Function, and discarded after derived metrics are stored. POV files are never uploaded by YEET.</p>
    <h2>ACCOUNT DATA</h2><p>If you sign in, Supabase stores your email or Google identity, handle, attempts, personal best, and derived measurement metrics. Guest play does not require an account.</p>
    <h2>DEVICE PERMISSIONS</h2><p>Motion access is requested from the YEET button. Camera and microphone access are requested only when Record POV is enabled. You can revoke access in browser settings.</p>
    <h2>OFFLINE DATA</h2><p>The PWA caches application files and the last leaderboard snapshot on your device. You can clear these through browser site-data controls.</p>
    <h2>DELETION</h2><p>Account deletion requires fresh email verification. Deleting the Auth user cascades to the profile, attempts, and personal best.</p>
  </>;
}

function Terms() {
  return <>
    <h2>PLAY SAFELY</h2><p>YEET involves throwing and catching your own device. Use a protective case, clear the area, stay away from people, animals, traffic, water, breakable objects, and overhead hazards. You assume the risk of damage or injury.</p>
    <h2>CASUAL RANKINGS</h2><p>The leaderboard is social entertainment, not a hardware-attested competition. No prizes are awarded. We may reject unreliable traces or remove abusive scores and accounts.</p>
    <h2>YOUR CONTENT</h2><p>POV recordings remain yours and local to your device. You are responsible for consent, lawful recording, and anything you choose to share.</p>
    <h2>AVAILABILITY</h2><p>Browser sensors, media encoders, authentication, and leaderboard services may be unavailable. YEET is provided as-is without a guarantee that every device can play ranked mode.</p>
  </>;
}
