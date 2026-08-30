import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { Session } from "@supabase/supabase-js";
import {
  Camera, ChevronRight, CircleAlert, CloudOff, Crown, Frown,
  RotateCcw, Settings, Trophy, UserRound, Video
} from "lucide-react";
import { Link } from "react-router-dom";
import { AccountDialog } from "../components/AccountDialog";
import { LeaderboardDialog } from "../components/LeaderboardDialog";
import { POVDialog } from "../components/POVDialog";
import { Button } from "../components/ui/Button";
import { Dialog } from "../components/ui/Dialog";
import { Switch } from "../components/ui/Switch";
import { useSession } from "../hooks/useSession";
import { pageColors, usePageChrome } from "../hooks/usePageChrome";
import { useYeetGame, type CompletedAttempt, type GamePhase } from "../hooks/useYeetGame";
import {
  cachedLeaderboard, getLeaderboard, isSupabaseConfigured, submitAttempt,
  type LeaderboardSnapshot, type ScoreSubmission
} from "../lib/backend";
import { hasAcceptedCurrentLegalTerms, recordLegalConsent } from "../lib/legal";
import { formatSeconds } from "../lib/utils";

export function YeetExperience() {
  const [tutorial, setTutorial] = useState(() => !hasAcceptedCurrentLegalTerms());
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

  const needsLegalConsent = !hasAcceptedCurrentLegalTerms();
  const finishTutorial = () => {
    if (needsLegalConsent) recordLegalConsent();
    localStorage.setItem("yeet.tutorial.complete", "true");
    setTutorial(false);
  };
  if (tutorial) return <Tutorial onContinue={finishTutorial} requiresConsent={needsLegalConsent} />;
  if (game.phase.kind !== "home") {
    return <>
      <GameScreen
        phase={game.phase}
        start={game.start}
        home={game.home}
        session={session}
        profile={profile}
        povRecording={game.isPovRecording}
        onAccount={() => setAccountOpen(true)}
      />
      <AccountDialog
        open={accountOpen}
        onOpenChange={setAccountOpen}
        session={session}
        profile={profile}
        onChanged={() => void queryClient.invalidateQueries({ queryKey: ["leaderboard"] })}
      />
    </>;
  }

  return (
    <main className="app-shell">
      <section className="game-card" aria-label="YEET home">
        <header className="topbar">
          <span className="topbar-spacer" aria-hidden />
          <p className="eyebrow">AIRTIME CHALLENGE</p>
          <button className="icon-button" onClick={() => setSettingsOpen(true)} aria-label="Open settings"><Settings /></button>
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
            <Switch id="pov" aria-label="Record POV" checked={game.povEnabled} disabled={game.isStarting} onCheckedChange={game.setPov} />
          </div>
          {game.povMessage && <p className="compact-warning" role="status">{game.povMessage}</p>}
          <button className="yeet-button" disabled={game.isStarting} onClick={() => void game.start()}>{game.isStarting ? "PREPARING…" : "YEET"}</button>
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

function Tutorial({ onContinue, requiresConsent }: { onContinue: () => void; requiresConsent: boolean }) {
  const [acknowledged, setAcknowledged] = useState(false);
  const canContinue = !requiresConsent || acknowledged;
  return (
    <main className="tutorial-screen"><section className="tutorial-card">
      <p className="eyebrow">WELCOME TO</p><h1>YEET</h1><p className="tutorial-deck">TAP → YEET → CATCH</p>
      <ol className="tutorial-steps">
        <li><span>1</span><div><b>CLEAR THE AREA</b><p>Use a protective case and a large, clear area away from people, animals, traffic, water, stairs, ledges, overhead hazards, and breakable objects.</p></div></li>
        <li><span>2</span><div><b>HOLD STILL</b><p>We run a half-second sensor check before each attempt.</p></div></li>
        <li><span>3</span><div><b>TOSS & CATCH</b><p>Make a controlled vertical toss within easy reach. Never chase a score or throw higher than you can safely catch.</p></div></li>
      </ol>
      <div className="safety-notice"><CircleAlert /><p><b>THROWING A PHONE CAN BE DANGEROUS.</b><br />A missed catch can cause device damage, data loss, property damage, serious injury, or death. Never play while driving, walking, impaired, or with a damaged phone or battery.</p></div>
      {requiresConsent ? (
        <label className="legal-consent">
          <input type="checkbox" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} />
          <span>I am 18 or older, understand that throwing a phone can cause injury or damage, and agree to the <Link to="/terms" target="_blank" rel="noreferrer">Terms of Use</Link> and acknowledge the <Link to="/privacy" target="_blank" rel="noreferrer">Privacy Notice</Link>.</span>
        </label>
      ) : (
        <p className="tutorial-legal-links"><Link to="/terms" target="_blank" rel="noreferrer">Terms of Use</Link><span>·</span><Link to="/privacy" target="_blank" rel="noreferrer">Privacy Notice</Link></p>
      )}
      <Button disabled={!canContinue} onClick={onContinue}>{requiresConsent ? "I AGREE — LET’S YEET" : "BACK TO YEET"}</Button>
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

export function GameScreen({ phase, start, home, session, profile, povRecording = false, onAccount }: {
  phase: GamePhase; start: () => Promise<void>; home: () => void; session: Session | null;
  profile?: LeaderboardSnapshot["current_user"]; povRecording?: boolean; onAccount: () => void;
}) {
  usePageChrome(phase.kind === "waiting" ? pageColors.yellow : pageColors.paper);
  if (phase.kind === "countdown") return <Countdown value={phase.value} />;
  if (phase.kind === "waiting") return <Waiting />;
  if (phase.kind === "airborne") return <Airborne start={phase.start} recording={povRecording} />;
  if (phase.kind === "invalid") return <Invalid reason={phase.reason} retry={start} home={home} canGoHome={phase.canGoHome} />;
  if (phase.kind === "caught") return <ResultFlow attempt={phase.attempt} retry={start} home={home} session={session} profile={profile} onAccount={onAccount} />;
  return null;
}

function Countdown({ value }: { value: 3 | 2 | 1 }) {
  const activeIndex = 3 - value;
  return (
    <main className="state-screen countdown-screen" aria-live="assertive" aria-label={`Countdown ${value}`}>
      <div className="countdown-number">{value}</div>
      <div className="countdown-footer">
        <div className="countdown-dots" aria-hidden>{[0, 1, 2, 3].map((index) => <i className={index === activeIndex ? "active" : ""} key={index} />)}</div>
        <p>HOLD STILL</p>
      </div>
    </main>
  );
}

function Waiting() {
  return (
    <main className="state-screen launch-screen" aria-live="assertive" aria-label="YEET. Waiting for release.">
      <div className="launch-word">YEET!</div>
      <div className="launch-footer"><i aria-hidden /><p>TOSS NOW · CATCH CLEAN</p></div>
    </main>
  );
}

function Airborne({ start, recording }: { start: number; recording: boolean }) {
  const [now, setNow] = useState(() => performance.now() / 1_000);
  useEffect(() => {
    let frame = 0;
    const tick = () => { setNow(performance.now() / 1_000); frame = requestAnimationFrame(tick); };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, []);
  return (
    <main className="state-screen airborne-screen" aria-label={recording ? "Airborne. POV recording." : "Airborne."}>
      {recording && <div className="recording-badge"><i /> RECORDING</div>}
      <div className="airtime-readout"><h1>{Math.max(0, now - start).toFixed(2)}<small>s</small></h1><p>AIRTIME</p></div>
    </main>
  );
}

function Invalid({ reason, retry, home, canGoHome }: { reason: string; retry: () => Promise<void>; home: () => void; canGoHome?: boolean }) {
  return (
    <main className="state-screen invalid-screen">
      <div className="no-yeet-mark"><Frown /></div>
      <h1>NO YEET</h1>
      <p>Couldn’t verify that one.</p>
      <p className="invalid-detail">{reason}</p>
      <div className="state-actions">
        <Button onClick={() => void retry()}>TRY AGAIN</Button>
        {canGoHome && <Button variant="ghost" onClick={home}>BACK HOME</Button>}
      </div>
    </main>
  );
}

type ResultStage = "catch" | "rankUp" | "result";
type ResultKind = "normal" | "personalBest" | "worldRecord";

function ResultFlow({ attempt, retry, home, session, profile, onAccount }: {
  attempt: CompletedAttempt; retry: () => Promise<void>; home: () => void; session: Session | null;
  profile?: LeaderboardSnapshot["current_user"]; onAccount: () => void;
}) {
  const queryClient = useQueryClient();
  const reducedMotion = usePrefersReducedMotion();
  const previousProfileRef = useRef(profile);
  const celebratedRef = useRef(false);
  const [stage, setStage] = useState<ResultStage>("catch");
  usePageChrome(stage === "rankUp" ? pageColors.black : pageColors.paper);
  const milliseconds = Math.round(attempt.result.airtime * 1_000);
  const estimate = useQuery({
    queryKey: ["candidate-rank", milliseconds],
    queryFn: () => getLeaderboard(milliseconds),
    enabled: !session && isSupabaseConfigured
  });
  const save = useMutation({
    mutationKey: ["submit-attempt", attempt.id],
    mutationFn: () => submitAttempt(attempt.id, attempt.samples),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["leaderboard"] })
  });
  const savedRef = useRef<ScoreSubmission | undefined>(undefined);
  savedRef.current = save.data;
  if (!previousProfileRef.current && profile && save.status === "idle") {
    previousProfileRef.current = profile;
  }

  useEffect(() => {
    if (session && profile && save.status === "idle") save.mutate();
  }, [profile, save.status, session]);

  useEffect(() => {
    const id = window.setTimeout(() => {
      if (savedRef.current?.is_personal_best) {
        celebratedRef.current = true;
        setStage("rankUp");
      } else {
        setStage("result");
      }
    }, reducedMotion ? 800 : 1_500);
    return () => window.clearTimeout(id);
  }, [attempt.id, reducedMotion]);

  useEffect(() => {
    if (stage !== "result" || !save.data?.is_personal_best || celebratedRef.current) return;
    celebratedRef.current = true;
    setStage("rankUp");
  }, [save.data, stage]);

  useEffect(() => {
    if (stage !== "rankUp") return;
    const id = window.setTimeout(() => setStage("result"), reducedMotion ? 1_200 : 3_000);
    return () => window.clearTimeout(id);
  }, [reducedMotion, stage]);

  if (stage === "catch") return <Catch result={attempt.result.airtime} reducedMotion={reducedMotion} />;
  if (stage === "rankUp" && save.data) {
    return <RankUp previousRank={previousProfileRef.current?.rank ?? undefined} newRank={save.data.rank} reducedMotion={reducedMotion} />;
  }

  const kind: ResultKind = save.data?.rank === 1
    ? "worldRecord"
    : save.data?.is_personal_best ? "personalBest" : "normal";
  return (
    <ResultScreen
      kind={kind}
      attempt={attempt}
      milliseconds={milliseconds}
      session={session}
      profile={profile}
      estimate={estimate.data?.candidate_rank}
      save={save}
      retry={retry}
      home={home}
      onAccount={onAccount}
    />
  );
}

function Catch({ result, reducedMotion }: { result: number; reducedMotion: boolean }) {
  return (
    <main className="state-screen catch-screen">
      {!reducedMotion && <Confetti />}
      <div className="catch-readout"><h1>{result.toFixed(2)}<small>s</small></h1><p>SECONDS AIRTIME</p></div>
      <div className="catch-celebration"><span aria-hidden>👏</span><b>NICE CATCH</b></div>
    </main>
  );
}

function Confetti() {
  return <div className="confetti" aria-hidden>{Array.from({ length: 32 }, (_, index) => <i key={index} />)}</div>;
}

function RankUp({ previousRank, newRank, reducedMotion }: { previousRank?: number; newRank: number; reducedMotion: boolean }) {
  return (
    <main className={`state-screen rank-up-screen ${reducedMotion ? "reduced" : ""}`}>
      {!reducedMotion && <Confetti />}
      <span>{previousRank ? `#${previousRank.toLocaleString()}` : "UNRANKED"}</span>
      <i aria-hidden>↓</i>
      <h1>#{newRank.toLocaleString()}</h1>
      <b>{previousRank ? "RANK UP" : "YOU’RE ON THE BOARD"}</b>
    </main>
  );
}

type SaveMutation = ReturnType<typeof useMutation<ScoreSubmission, Error, void>>;

function ResultScreen({
  kind, attempt, milliseconds, session, profile, estimate, save, retry, home, onAccount
}: {
  kind: ResultKind;
  attempt: CompletedAttempt;
  milliseconds: number;
  session: Session | null;
  profile?: LeaderboardSnapshot["current_user"];
  estimate?: number | null;
  save: SaveMutation;
  retry: () => Promise<void>;
  home: () => void;
  onAccount: () => void;
}) {
  const [povOpen, setPovOpen] = useState(false);
  const availablePOV = attempt.pov.kind === "available" ? attempt.pov.blob : undefined;
  return (
    <main className="state-screen result-screen">
      {kind === "personalBest" && <div className="achievement-badge pb-badge"><Trophy /> NEW PB!</div>}
      {kind === "worldRecord" && <div className="world-result-badge"><Crown /><b>WORLD RECORD</b></div>}

      <div className="result-readout"><h1>{(milliseconds / 1_000).toFixed(2)}<small>s</small></h1><p>AIRTIME</p></div>

      {kind === "normal" && <ResultCloudStatus session={session} profile={profile} estimate={estimate} save={save} onAccount={onAccount} />}
      {kind === "worldRecord" && <p className="world-record-copy">YOU ARE #1</p>}

      <div className="state-actions result-actions">
        <Button disabled={attempt.pov.kind === "finalizing"} onClick={() => void retry()}>YEET AGAIN</Button>
        <Button variant="secondary" onClick={home}>BACK HOME</Button>
        {attempt.pov.kind === "finalizing" && <Button variant="secondary" disabled>PROCESSING POV…</Button>}
        {availablePOV && <Button variant="secondary" onClick={() => setPovOpen(true)}><Video /> VIEW POV</Button>}
        {attempt.pov.kind === "failed" && <p className="result-pov-error" role="status">{attempt.pov.message}</p>}
      </div>

      {availablePOV && (
        <POVDialog
          open={povOpen}
          onOpenChange={setPovOpen}
          blob={availablePOV}
          airtimeMs={milliseconds}
          rank={save.data?.rank}
          candidateRank={estimate ?? undefined}
        />
      )}
    </main>
  );
}

function ResultCloudStatus({ session, profile, estimate, save, onAccount }: {
  session: Session | null;
  profile?: LeaderboardSnapshot["current_user"];
  estimate?: number | null;
  save: SaveMutation;
  onAccount: () => void;
}) {
  if (!isSupabaseConfigured) return <p className="result-note warning">Leaderboard saving is unavailable until Supabase is configured.</p>;
  if (!session) return <button className="result-signin" onClick={onAccount}><b>{estimate ? `ESTIMATED RANK #${estimate}` : "RANK ESTIMATE PENDING"}</b><span>Sign in to save this score.</span><ChevronRight /></button>;
  if (!profile) return <button className="result-signin" onClick={onAccount}><b>CHOOSE A HANDLE</b><span>Your valid score is ready to save.</span><ChevronRight /></button>;
  if (save.isPending) return <p className="result-note">Saving verified score…</p>;
  if (save.isError) return <div className="save-error"><p>{save.error.message}</p><Button variant="secondary" onClick={() => save.mutate()}>RETRY SAVE</Button></div>;
  if (save.data) return null;
  return <p className="result-note">Preparing verified submission…</p>;
}

function usePrefersReducedMotion() {
  const [reduced, setReduced] = useState(() => typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  useEffect(() => {
    if (typeof window.matchMedia !== "function") return;
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(query.matches);
    query.addEventListener?.("change", update);
    return () => query.removeEventListener?.("change", update);
  }, []);
  return reduced;
}
