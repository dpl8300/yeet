import { useCallback, useEffect, useRef, useState } from "react";
import { AirtimeDetector, type DetectionResult, type RawTraceSample } from "@yeet/airtime-core";
import {
  listenForMotion,
  motionCapability,
  requestMotionPermission,
  requestWakeLock,
  runStationaryPreflight
} from "../lib/device-motion";
import { POVRecorder, supportsPovRecording } from "../lib/pov";

export type CompletedAttempt = {
  id: string;
  result: DetectionResult;
  samples: RawTraceSample[];
  pov:
    | { kind: "none" }
    | { kind: "finalizing" }
    | { kind: "available"; blob: Blob }
    | { kind: "failed"; message: string };
};

export type GamePhase =
  | { kind: "home" }
  | { kind: "countdown"; value: 3 | 2 | 1 }
  | { kind: "waiting" }
  | { kind: "airborne"; start: number }
  | { kind: "caught"; attempt: CompletedAttempt }
  | { kind: "invalid"; reason: string; canGoHome?: boolean };

const wait = (milliseconds: number) => new Promise((resolve) => window.setTimeout(resolve, milliseconds));

export function useYeetGame() {
  const [phase, setPhase] = useState<GamePhase>({ kind: "home" });
  const [povEnabled, setPovEnabled] = useState(() => localStorage.getItem("yeet.pov") === "true");
  const [povMessage, setPovMessage] = useState<string>();
  const [isStarting, setIsStarting] = useState(false);
  const [isPovRecording, setIsPovRecording] = useState(false);
  const cleanupRef = useRef<() => void>(() => undefined);
  const runRef = useRef(0);
  const startingRef = useRef(false);

  const cleanup = useCallback(() => {
    runRef.current += 1;
    cleanupRef.current();
    cleanupRef.current = () => undefined;
    setIsPovRecording(false);
  }, []);

  const invalidate = useCallback((reason: string) => {
    cleanup();
    setPhase({ kind: "invalid", reason });
  }, [cleanup]);

  const setPov = useCallback((enabled: boolean) => {
    if (enabled && !supportsPovRecording()) {
      setPovMessage("POV recording needs camera, microphone, and MediaRecorder support in this browser.");
      setPovEnabled(false);
      localStorage.setItem("yeet.pov", "false");
      return;
    }
    setPovMessage(undefined);
    setPovEnabled(enabled);
    localStorage.setItem("yeet.pov", String(enabled));
  }, []);

  const start = useCallback(async () => {
    if (startingRef.current) return;
    cleanup();
    const run = runRef.current;
    startingRef.current = true;
    setIsStarting(true);
    const capability = motionCapability();
    setPovMessage(undefined);
    if (capability === "view-only") {
      setPhase({
        kind: "invalid",
        reason: "This browser cannot read device motion. You can still view the leaderboard.",
        canGoHome: true
      });
      startingRef.current = false;
      setIsStarting(false);
      return;
    }

    let recorder: POVRecorder | undefined;
    let wakeLock: { release: () => Promise<void> } | undefined;
    let hiddenDuringPreparation = false;
    const preparationVisibility = () => { if (document.hidden) hiddenDuringPreparation = true; };
    document.addEventListener("visibilitychange", preparationVisibility);
    cleanupRef.current = () => {
      document.removeEventListener("visibilitychange", preparationVisibility);
      recorder?.discard();
      void wakeLock?.release();
    };
    try {
      await requestMotionPermission();
      if (runRef.current !== run) return;

      if (povEnabled) {
        try {
          recorder = new POVRecorder();
          await recorder.prepare();
        } catch {
          recorder?.discard();
          recorder = undefined;
          setPovEnabled(false);
          localStorage.setItem("yeet.pov", "false");
          setPovMessage("POV was disabled because this device could not prepare the camera and microphone.");
        }
      }
      wakeLock = await requestWakeLock();
      if (runRef.current !== run) return;

      setPhase({ kind: "countdown", value: 3 });
      const preflightStartedAt = performance.now();
      const preflight = await runStationaryPreflight();
      if (runRef.current !== run) return;
      if (hiddenDuringPreparation) throw new Error("page-hidden");
      if (!preflight.ok) throw new Error(`preflight-${preflight.reason}`);

      await wait(Math.max(0, 1_000 - (performance.now() - preflightStartedAt)));
      if (runRef.current !== run) { recorder?.discard(); return; }
      if (hiddenDuringPreparation) throw new Error("page-hidden");

      for (const value of [2, 1] as const) {
        setPhase({ kind: "countdown", value });
        await wait(1_000);
        if (runRef.current !== run) { recorder?.discard(); return; }
        if (hiddenDuringPreparation) throw new Error("page-hidden");
      }

      const detector = new AirtimeDetector();
      const samples: RawTraceSample[] = [];
      detector.arm();
      if (recorder) {
        try { recorder.start(); }
        catch {
          recorder.discard();
          recorder = undefined;
          setPovEnabled(false);
          localStorage.setItem("yeet.pov", "false");
          setPovMessage("POV was disabled because recording could not start at full quality.");
        }
      }
      setIsPovRecording(Boolean(recorder));
      setPhase({ kind: "waiting" });

      let stopped = false;
      let stopMotion: () => void = () => undefined;
      let timeout = 0;
      const visibility = () => { if (document.hidden) invalidate("The attempt ended because the page was hidden."); };
      const release = () => {
        if (stopped) return;
        stopped = true;
        stopMotion();
        window.clearTimeout(timeout);
        document.removeEventListener("visibilitychange", visibility);
        void wakeLock?.release();
      };
      document.removeEventListener("visibilitychange", preparationVisibility);
      cleanupRef.current = () => { release(); recorder?.discard(); };
      document.addEventListener("visibilitychange", visibility);
      timeout = window.setTimeout(() => invalidate("No throw detected within 15 seconds."), 15_100);

      stopMotion = listenForMotion(async (motion, raw) => {
        if (stopped || runRef.current !== run) return;
        samples.push(raw);
        const state = detector.process(motion);
        if (state.kind === "airborne" || state.kind === "possible-landing") {
          setPhase((current) => current.kind === "airborne" ? current : { kind: "airborne", start: state.kind === "airborne" ? state.start : state.start });
        }
        if (state.kind === "invalid") {
          release();
          recorder?.discard();
          setIsPovRecording(false);
          setPhase({ kind: "invalid", reason: invalidCopy(state.reason) });
        }
        if (state.kind === "finished") {
          release();
          setIsPovRecording(false);
          const attemptId = crypto.randomUUID();
          setPhase({
            kind: "caught",
            attempt: {
              id: attemptId,
              result: state.result,
              samples,
              pov: recorder ? { kind: "finalizing" } : { kind: "none" }
            }
          });

          if (recorder) {
            void recorder.stop().then((blob) => {
              if (runRef.current !== run) return;
              setPhase((current) => current.kind === "caught" && current.attempt.id === attemptId
                ? { ...current, attempt: { ...current.attempt, pov: { kind: "available", blob } } }
                : current);
            }).catch(() => {
              if (runRef.current !== run) return;
              const message = "Your airtime was measured, but the POV recording could not be finalized.";
              setPovMessage(message);
              setPhase((current) => current.kind === "caught" && current.attempt.id === attemptId
                ? { ...current, attempt: { ...current.attempt, pov: { kind: "failed", message } } }
                : current);
            });
          }
        }
      });
    } catch (error) {
      document.removeEventListener("visibilitychange", preparationVisibility);
      cleanupRef.current = () => undefined;
      recorder?.discard();
      void wakeLock?.release();
      const reason = error instanceof Error ? error.message : "sensor-error";
      setPhase({ kind: "invalid", reason: preparationCopy(reason), canGoHome: true });
    } finally {
      if (runRef.current === run) {
        startingRef.current = false;
        setIsStarting(false);
      }
    }
  }, [cleanup, invalidate, povEnabled]);

  const home = useCallback(() => {
    startingRef.current = false;
    setIsStarting(false);
    cleanup();
    setPhase({ kind: "home" });
  }, [cleanup]);
  useEffect(() => cleanup, [cleanup]);

  return { phase, start, home, povEnabled, setPov, povMessage, isStarting, isPovRecording };
}

function invalidCopy(reason: string) {
  const copy: Record<string, string> = {
    "no-throw": "No throw detected. Keep the phone still until the countdown ends, then toss.",
    "too-short": "That airtime was too short to count. Try a clean, controlled toss.",
    "sample-gap": "Motion samples became unreliable during the flight.",
    "non-monotonic-timestamp": "The browser reported invalid motion timing.",
    "invalid-sample": "The browser reported an invalid motion sample."
  };
  return copy[reason] ?? "That attempt could not be measured reliably.";
}

function preparationCopy(reason: string) {
  if (reason === "page-hidden") return "The attempt ended because the page was hidden.";
  if (reason === "motion-permission-denied") return "Motion access was denied. Enable Motion & Orientation Access in browser settings.";
  if (reason === "pov-unsupported") return "This browser cannot complete the full POV recording and export pipeline. Turn Record POV off to play.";
  if (reason.includes("preflight-not-enough-samples") || reason.includes("preflight-unreliable-sampling")) return "The motion sensor sample rate is not reliable enough for gameplay.";
  if (reason.includes("preflight-uncalibrated")) return "The stationary sensor check failed. Hold the phone still through the countdown and try again.";
  return "YEET could not prepare the device sensors. Try again in Safari or Chrome on a supported phone.";
}
