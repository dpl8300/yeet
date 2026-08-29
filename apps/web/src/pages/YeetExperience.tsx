import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { Session } from "@supabase/supabase-js";
import {
  BarChart3, Camera, ChevronRight, CircleAlert, CloudOff, Crown, RotateCcw,
  Settings, ShieldCheck, Trophy, UserRound, Video
} from "lucide-react";
import { Link } from "react-router-dom";
import { AccountDialog } from "../components/AccountDialog";
import { LeaderboardDialog } from "../components/LeaderboardDialog";
import { POVDialog } from "../components/POVDialog";
import { Button } from "../components/ui/Button";
import { Dialog } from "../components/ui/Dialog";
import { Switch } from "../components/ui/Switch";
import { useSession } from "../hooks/useSession";
import { useYeetGame, type CompletedAttempt, type GamePhase } from "../hooks/useYeetGame";
import {
  cachedLeaderboard, getLeaderboard, isSupabaseConfigured, submitAttempt,
  type LeaderboardSnapshot, type ScoreSubmission
} from "../lib/backend";
import { formatSeconds } from "../lib/utils";

export function YeetExperience() {
  const [tutorial, setTutorial] = useState(() => localStorage.getItem("yeet.tutorial.complete") !== "true");
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [leaderboardOpen, setLeaderboardOpen] = useState(false);
  const [accountOpen, setAccountOpen] = useState(false);
  const game = useYeetGame();
  const { session } = useSession();
  const queryClient = useQueryClient();
  const leaderboard = useQuery({
    queryKey: ["leaderboard"],
    queryFn: () => getLeaderboard(),
    placeholderData: cachedLeaderboard,
    enabled: isSupabaseConfigured
  });
  const snapshot = leaderboard.data;
  const profile = snapshot?.current_user;

  const finishTutorial = () => {
    localStorage.setItem("yeet.tutorial.complete", "true");
    setTutorial(false);
  };
  if (tutorial) return <Tutorial onContinue={finishTutorial} />;
  if (game.phase.kind !== "home") {
    return <>
      <GameScreen phase={game.phase} start={game.start} home={game.home} session={session} profile={profile} onAccount={() => setAccountOpen(true)} />
      <AccountDialog open={accountOpen} onOpenChange={setAccountOpen} session={session} profile={profile} onChanged={() => void queryClient.invalidateQueries({ queryKey: ["leaderboard"] })} />
    </>;
  }

  return (
    <main className="app-shell">
      <section className="game-card" aria-label="YEET home">
        <header className="topbar">
          <button className="icon-button" onClick={() => setSettingsOpen(true)} aria-label="Open settings"><Settings /></button>
          <p className="eyebrow">AIRTIME CHALLENGE</p>
          <button className="icon-button" onClick={() => setLeaderboardOpen(true)} aria-label="Open leaderboard"><BarChart3 /></button>
        </header>
        <div className="hero-copy"><h1>YEET</h1><p>THROW HIGH.<br />CATCH CLEAN.</p></div>
        <div className="leaderboard-stack">
          <LeaderboardPreview snapshot={snapshot} loading={leaderboard.isLoading} failed={leaderboard.isError} onOpen={() => setLeaderboardOpen(true)} />
          <button className="player-row" onClick={() => setAccountOpen(true)}>
            <span>{profile?.rank ? `#${profile.rank}` : "YOU"}</span>
            <span>{profile ? `@${profile.handle} · ${formatSeconds(profile.airtime_ms)}` : session ? "CHOOSE YOUR HANDLE" : "PLAY AS GUEST"}</span>
            <ChevronRight />
          </button>
        </div>
        <div className="home-controls">
          <div className="pov-control">
            <span className="pov-icon"><Camera /></span>
            <label htmlFor="pov"><b>RECORD POV</b><small>CAMERA + MIC · DEVICE ONLY</small></label>
            <Switch id="pov" aria-label="Record POV" checked={game.povEnabled} onCheckedChange={game.setPov} />
          </div>
          {game.povMessage && <p className="compact-warning" role="status">{game.povMessage}</p>}
          <button className="yeet-button" onClick={game.start}>YEET</button>
          <p className="safety-line">Clear the area. Use a case. Never throw toward people, animals, traffic, or breakable objects.</p>
          <footer><Link to="/privacy">Privacy</Link><span>·</span><Link to="/terms">Terms</Link></footer>
        </div>
      </section>
      <LeaderboardDialog open={leaderboardOpen} onOpenChange={setLeaderboardOpen} snapshot={snapshot} stale={leaderboard.isFetching} error={leaderboard.error instanceof Error ? leaderboard.error.message : undefined} />
      <AccountDialog open={accountOpen} onOpenChange={setAccountOpen} session={session} profile={profile} onChanged={() => void queryClient.invalidateQueries({ queryKey: ["leaderboard"] })} />
      <SettingsDialog open={settingsOpen} onOpenChange={setSettingsOpen} onTutorial={() => { setSettingsOpen(false); setTutorial(true); }} accountLabel={profile ? `@${profile.handle}` : session ? "Finish profile" : "Sign in"} onAccount={() => { setSettingsOpen(false); setAccountOpen(true); }} />
    </main>
  );
}

function Tutorial({ onContinue }: { onContinue: () => void }) {
  return (
    <main className="tutorial-screen"><section className="tutorial-card">
      <p className="eyebrow">WELCOME TO</p><h1>YEET</h1><p className="tutorial-deck">TAP → YEET → CATCH</p>
      <ol className="tutorial-steps">
        <li><span>1</span><div><b>CLEAR THE AREA</b><p>Use a case. Stay away from people, pets, traffic, water, and anything breakable.</p></div></li>
        <li><span>2</span><div><b>HOLD STILL</b><p>We run a half-second sensor check before each attempt.</p></div></li>
        <li><span>3</span><div><b>TOSS & CATCH</b><p>Keep it controlled. YEET measures the time between release and catch.</p></div></li>
      </ol>
      <div className="safety-notice"><CircleAlert /><p><b>YOUR PHONE. YOUR RISK.</b><br />Never play where a missed catch could hurt someone or damage property.</p></div>
      <Button onClick={onContinue}>LET’S YEET</Button>
    </section></main>
  );
}

function LeaderboardPreview({ snapshot, loading, failed, onOpen }: { snapshot?: LeaderboardSnapshot; loading: boolean; failed: boolean; onOpen: () => void }) {
  const leaders = snapshot?.leaders.slice(0, 10) ?? [];
  return (
    <div className="leaderboard-card">
      <button className="section-title" onClick={onOpen}><span>WORLD LEADERS</span><span>{failed ? <CloudOff /> : loading ? "SYNC" : "LIVE"}</span></button>
      <div className="leaderboard-rows" role="region" aria-label="Top ten leaderboard" tabIndex={leaders.length ? 0 : -1}>
        {!leaders.length && <button className="empty-preview" onClick={onOpen}>{failed || !isSupabaseConfigured ? "LEADERBOARD UNAVAILABLE" : loading ? "LOADING SCORES…" : "BE FIRST ON THE BOARD"}</button>}
        {leaders.map((entry) => <button className="leader-row" onClick={onOpen} key={entry.user_id}><strong>{entry.rank == null ? "—" : `#${entry.rank}`}</strong><span>@{entry.handle}</span><b>{formatSeconds(entry.airtime_ms)}</b></button>)}
      </div>
    </div>
  );
}

function SettingsDialog({ open, onOpenChange, onTutorial, accountLabel, onAccount }: {
  open: boolean; onOpenChange: (open: boolean) => void; onTutorial: () => void; accountLabel: string; onAccount: () => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange} title="SETTINGS" description="Browser capabilities and your YEET profile.">
      <div className="settings-list">
        <button onClick={onAccount}><UserRound /><span><b>ACCOUNT</b><small>{accountLabel}</small></span><ChevronRight /></button>
        <button onClick={onTutorial}><RotateCcw /><span><b>REPLAY TUTORIAL</b><small>Safety and how to play</small></span><ChevronRight /></button>
      </div>
    </Dialog>
  );
}

export function GameScreen({ phase, start, home, session, profile, onAccount }: {
  phase: GamePhase; start: () => Promise<void>; home: () => void; session: Session | null;
  profile?: LeaderboardSnapshot["current_user"]; onAccount: () => void;
}) {
  if (phase.kind === "preflight") return <StatePage tone="paper" mark="◎" title="HOLD STILL" detail="Checking sensor calibration for 500ms…" />;
  if (phase.kind === "countdown") return <StatePage tone="paper" mark={String(phase.value)} title={phase.value === 1 ? "GET READY" : ""} detail="Keep a clean grip." />;
  if (phase.kind === "waiting") return <StatePage tone="yellow" mark="↑" title="YEET" detail="Toss now. Catch clean." />;
  if (phase.kind === "airborne") return <Airborne start={phase.start} />;
  if (phase.kind === "invalid") return <Invalid reason={phase.reason} retry={start} home={home} />;
  if (phase.kind === "caught") return <ResultScreen attempt={phase.attempt} retry={start} home={home} session={session} profile={profile} onAccount={onAccount} />;
  return null;
}

function StatePage({ tone, mark, title, detail }: { tone: "yellow" | "paper"; mark: string; title: string; detail: string }) {
  return <main className={`state-screen ${tone === "yellow" ? "yellow-screen" : "paper-screen"}`} aria-live="assertive"><div className="action-mark">{mark}</div><h1>{title}</h1><p>{detail}</p></main>;
}

function Airborne({ start }: { start: number }) {
  const [now, setNow] = useState(() => performance.now() / 1000);
  useEffect(() => { const id = window.setInterval(() => setNow(performance.now() / 1000), 16); return () => window.clearInterval(id); }, []);
  return <main className="state-screen airborne-screen" aria-label="Airborne"><div className="flight-phone">▯</div><p className="eyebrow">AIRBORNE</p><h1>{Math.max(0, now - start).toFixed(2)}<small>s</small></h1><p>Eyes on the catch.</p></main>;
}

function Invalid({ reason, retry, home }: { reason: string; retry: () => Promise<void>; home: () => void }) {
  return <main className="state-screen invalid-screen"><CircleAlert className="state-icon" /><p className="eyebrow">INVALID ATTEMPT</p><h1>NO SCORE</h1><p>{reason}</p><div className="state-actions"><Button onClick={retry}>TRY AGAIN</Button><Button variant="secondary" onClick={home}>BACK HOME</Button></div></main>;
}

function ResultScreen({ attempt, retry, home, session, profile, onAccount }: {
  attempt: CompletedAttempt; retry: () => Promise<void>; home: () => void; session: Session | null;
  profile?: LeaderboardSnapshot["current_user"]; onAccount: () => void;
}) {
  const queryClient = useQueryClient();
  const [caught, setCaught] = useState(true);
  const [povOpen, setPovOpen] = useState(false);
  const milliseconds = Math.round(attempt.result.airtime * 1000);
  const estimate = useQuery({ queryKey: ["candidate-rank", milliseconds], queryFn: () => getLeaderboard(milliseconds), enabled: !session && isSupabaseConfigured });
  const save = useMutation({
    mutationKey: ["submit-attempt", attempt.id], mutationFn: () => submitAttempt(attempt.id, attempt.samples),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["leaderboard"] })
  });
  useEffect(() => { const id = window.setTimeout(() => setCaught(false), 750); return () => window.clearTimeout(id); }, []);
  useEffect(() => { if (session && profile && save.status === "idle") save.mutate(); }, [profile, save, session]);
  if (caught) return <main className="state-screen caught-screen"><div className="catch-ring"><ShieldCheck /></div><h1>CAUGHT!</h1><p>Clean hands. Valid flight.</p></main>;

  const saved = save.data;
  return (
    <main className={`state-screen result-screen ${saved?.rank === 1 ? "world-record" : saved?.is_personal_best ? "personal-best" : ""}`}>
      <ResultBadge saved={saved} previousRank={profile?.rank ?? undefined} />
      <p className="eyebrow">AIRTIME</p><h1>{(milliseconds / 1000).toFixed(2)}<small>s</small></h1>
      <ResultCloudStatus attempt={attempt} session={session} profile={profile} estimate={estimate.data?.candidate_rank} save={save} onAccount={onAccount} />
      {attempt.pov && <Button variant="secondary" onClick={() => setPovOpen(true)}><Video /> VIEW POV</Button>}
      <div className="state-actions"><Button onClick={retry}>YEET AGAIN</Button><Button variant="ghost" onClick={home}>BACK HOME</Button></div>
      {attempt.pov && <POVDialog open={povOpen} onOpenChange={setPovOpen} blob={attempt.pov} airtimeMs={milliseconds} rank={saved?.rank ?? estimate.data?.candidate_rank ?? undefined} />}
    </main>
  );
}

function ResultBadge({ saved, previousRank }: { saved?: ScoreSubmission; previousRank?: number }) {
  if (!saved) return <div className="achievement-badge">VALID FLIGHT</div>;
  if (saved.rank === 1) return <div className="achievement-badge world-badge"><Crown /> WORLD RECORD</div>;
  if (saved.is_personal_best && previousRank && saved.rank < previousRank) return <div className="achievement-badge rank-badge">RANK UP · #{saved.rank}</div>;
  if (saved.is_personal_best) return <div className="achievement-badge pb-badge"><Trophy /> PERSONAL BEST</div>;
  return <div className="achievement-badge">SCORE SAVED · #{saved.rank}</div>;
}

type SaveMutation = ReturnType<typeof useMutation<ScoreSubmission, Error, void>>;
function ResultCloudStatus({ attempt, session, profile, estimate, save, onAccount }: {
  attempt: CompletedAttempt; session: Session | null; profile?: LeaderboardSnapshot["current_user"];
  estimate?: number | null; save: SaveMutation; onAccount: () => void;
}) {
  if (!isSupabaseConfigured) return <p className="result-note warning">Leaderboard saving is unavailable until Supabase is configured.</p>;
  if (!session) return <button className="result-signin" onClick={onAccount}><b>{estimate ? `ESTIMATED RANK #${estimate}` : "RANK ESTIMATE PENDING"}</b><span>Sign in to save this score.</span><ChevronRight /></button>;
  if (!profile) return <button className="result-signin" onClick={onAccount}><b>CHOOSE A HANDLE</b><span>Your valid score is ready to save.</span><ChevronRight /></button>;
  if (save.isPending) return <p className="result-note">Saving verified score…</p>;
  if (save.isError) return <div className="save-error"><p>{save.error.message}</p><Button variant="secondary" onClick={() => save.mutate()}>RETRY SAVE</Button></div>;
  if (save.data) return <p className="result-note"><b>SAVED · RANK #{save.data.rank}</b><br />Personal best {formatSeconds(save.data.personal_best_ms)}</p>;
  return <p className="result-note">Preparing verified submission…</p>;
}
