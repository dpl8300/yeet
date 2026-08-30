import * as DialogPrimitive from "@radix-ui/react-dialog";
import { Play, Share2, TriangleAlert } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  createBrandedVideo,
  shareVideo,
  supportsBrandedPovExport
} from "../lib/pov";
import { pageColors, usePageChrome } from "../hooks/usePageChrome";
import { trackEvent, type AccountState } from "../lib/analytics";
import { Button } from "./ui/Button";

type POVStage = "replay" | "exporting" | "share" | "failed";

export function POVDialog({
  open,
  onOpenChange,
  blob,
  airtimeMs,
  rank,
  candidateRank,
  accountState = "guest",
  resultKind = "normal"
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  blob: Blob;
  airtimeMs: number;
  rank?: number;
  candidateRank?: number;
  accountState?: AccountState;
  resultKind?: "normal" | "personalBest" | "worldRecord";
}) {
  const rawUrl = useMemo(() => URL.createObjectURL(blob), [blob]);
  const rawVideoRef = useRef<HTMLVideoElement>(null);
  const exportRunRef = useRef(0);
  const wasOpenRef = useRef(false);
  const playbackStartedRef = useRef(false);
  const playbackCompletedRef = useRef(false);
  const closingRef = useRef(false);
  const [stage, setStage] = useState<POVStage>("replay");
  const [isPlaying, setIsPlaying] = useState(false);
  const [shareBlob, setShareBlob] = useState<Blob>();
  const [shareUrl, setShareUrl] = useState<string>();
  const [message, setMessage] = useState<string>();
  const canBrand = supportsBrandedPovExport();
  const exportFormat = canBrand ? "branded" : "raw";
  const analyticsResultKind = resultKind === "personalBest"
    ? "personal_best"
    : resultKind === "worldRecord" ? "world_record" : "normal";
  const formattedAirtime = (airtimeMs / 1_000).toFixed(2);
  usePageChrome(open ? pageColors.black : undefined);

  useEffect(() => () => URL.revokeObjectURL(rawUrl), [rawUrl]);
  useEffect(() => {
    if (!shareBlob) {
      setShareUrl(undefined);
      return;
    }
    const url = URL.createObjectURL(shareBlob);
    setShareUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [shareBlob]);
  useEffect(() => {
    if (open && !wasOpenRef.current) {
      wasOpenRef.current = true;
      closingRef.current = false;
      playbackStartedRef.current = false;
      playbackCompletedRef.current = false;
      trackEvent("pov_viewed", { account_state: accountState, result_kind: analyticsResultKind });
      return;
    }
    if (open) return;
    wasOpenRef.current = false;
    exportRunRef.current += 1;
    rawVideoRef.current?.pause();
    setIsPlaying(false);
    setStage("replay");
    setShareBlob(undefined);
    setMessage(undefined);
  }, [accountState, analyticsResultKind, open]);

  const changeOpen = (nextOpen: boolean) => {
    if (!nextOpen && open && !closingRef.current) {
      closingRef.current = true;
      if (stage === "exporting") {
        exportRunRef.current += 1;
        trackEvent("pov_export_result", { outcome: "cancelled", format: exportFormat });
      }
      trackEvent("pov_closed", { account_state: accountState, stage });
    }
    onOpenChange(nextOpen);
  };

  const togglePlayback = async () => {
    const video = rawVideoRef.current;
    if (!video) return;
    if (!video.paused) {
      video.pause();
      setIsPlaying(false);
      return;
    }
    if (video.ended) video.currentTime = 0;
    try {
      await video.play();
      setIsPlaying(true);
    } catch {
      setMessage("Tap play again to start your POV.");
    }
  };

  const prepareShare = async () => {
    rawVideoRef.current?.pause();
    setIsPlaying(false);
    setMessage(undefined);
    setStage("exporting");
    trackEvent("pov_export_started", { account_state: accountState, format: exportFormat });
    const run = ++exportRunRef.current;
    try {
      const output = canBrand
        ? await createBrandedVideo(blob, airtimeMs, rank, candidateRank)
        : blob;
      if (run !== exportRunRef.current) return;
      setShareBlob(output);
      setMessage(canBrand ? undefined : "Branded export is unavailable here, so this preview uses your original POV.");
      setStage("share");
      trackEvent("pov_export_result", { outcome: "success", format: exportFormat });
    } catch (error) {
      if (run !== exportRunRef.current) return;
      setMessage(exportErrorMessage(error));
      setStage("failed");
      trackEvent("pov_export_result", { outcome: "failure", format: exportFormat });
    }
  };

  const returnToReplay = () => {
    if (stage === "exporting") trackEvent("pov_export_result", { outcome: "cancelled", format: exportFormat });
    exportRunRef.current += 1;
    setStage("replay");
    setShareBlob(undefined);
    setMessage(undefined);
  };

  const share = async () => {
    if (!shareBlob) return;
    setMessage(undefined);
    try {
      const outcome = await shareVideo(shareBlob);
      trackEvent("pov_share_result", { outcome, format: exportFormat });
      setMessage(outcome === "shared" ? "SHARED" : "SHARING ISN’T AVAILABLE HERE · SAVED TO DOWNLOADS");
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        trackEvent("pov_share_result", { outcome: "cancelled", format: exportFormat });
        return;
      }
      trackEvent("pov_share_result", { outcome: "failure", format: exportFormat });
      setMessage(error instanceof Error ? error.message : "The video could not be shared.");
    }
  };

  return (
    <DialogPrimitive.Root open={open} onOpenChange={changeOpen}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="pov-overlay" />
        <DialogPrimitive.Content className="pov-fullscreen" aria-describedby={undefined}>
          <DialogPrimitive.Title className="sr-only">Your POV</DialogPrimitive.Title>

          {stage === "replay" && (
            <div className="pov-replay-screen">
              <video
                ref={rawVideoRef}
                className="pov-replay-video"
                src={rawUrl}
                playsInline
                onClick={() => void togglePlayback()}
                onPlay={() => {
                  setIsPlaying(true);
                  if (!playbackStartedRef.current) {
                    playbackStartedRef.current = true;
                    trackEvent("pov_playback_started", { account_state: accountState, stage: "replay" });
                  }
                }}
                onPause={() => setIsPlaying(false)}
                onEnded={() => {
                  setIsPlaying(false);
                  if (!playbackCompletedRef.current) {
                    playbackCompletedRef.current = true;
                    trackEvent("pov_playback_completed", { account_state: accountState, stage: "replay" });
                  }
                  if (rawVideoRef.current) rawVideoRef.current.currentTime = 0;
                }}
              />
              <div className="pov-replay-gradient" aria-hidden />
              <div className="pov-replay-content">
                <div className="pov-replay-heading">
                  <div><strong>{formattedAirtime}s</strong><span>AIRTIME</span></div>
                  <b>YEET</b>
                </div>

                {!isPlaying && (
                  <button className="pov-play" onClick={() => void togglePlayback()} aria-label="Play POV video">
                    <Play />
                  </button>
                )}

                <div className="pov-replay-footer">
                  {message && <p className="pov-inline-status" role="status">{message}</p>}
                  <div className="pov-replay-actions">
                    <DialogPrimitive.Close asChild><Button className="pov-dark-button" variant="secondary">DONE</Button></DialogPrimitive.Close>
                    <Button onClick={() => void prepareShare()}>SHARE</Button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {stage === "exporting" && (
            <div className="pov-share-state">
              <div className="pov-spinner" aria-hidden />
              <h2>CREATING YOUR YEET…</h2>
              <button className="pov-text-action" onClick={returnToReplay}>CANCEL</button>
            </div>
          )}

          {stage === "failed" && (
            <div className="pov-share-state">
              <TriangleAlert />
              <h2>SHARE VIDEO FAILED</h2>
              <p>{message}</p>
              <div className="pov-state-actions">
                <Button onClick={() => void prepareShare()}>TRY AGAIN</Button>
                <Button className="pov-dark-button" variant="secondary" onClick={returnToReplay}>DONE</Button>
              </div>
            </div>
          )}

          {stage === "share" && shareUrl && (
            <div className="pov-share-screen">
              <header>
                <button onClick={returnToReplay}>DONE</button>
                <h2>SHARE</h2>
                <span aria-hidden />
              </header>
              <video className="pov-share-preview" src={shareUrl} autoPlay loop muted playsInline aria-label="Looping share preview" />
              {message && <p className="pov-share-status" role="status">{message}</p>}
              <div className="pov-share-actions">
                <Button onClick={() => void share()}><Share2 /> SAVE OR SHARE</Button>
              </div>
            </div>
          )}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function exportErrorMessage(error: unknown) {
  if (!(error instanceof Error)) return "The share video could not be created. Please try again.";
  const knownMessages: Record<string, string> = {
    "pov-replay-failed": "The POV recording could not be loaded for export.",
    "pov-audio-export-unsupported": "This browser could not include POV audio in the share video.",
    "pov-export-failed": "The browser could not finish the share video.",
    "pov-branded-export-unsupported": "Branded video export is unavailable in this browser."
  };
  return knownMessages[error.message] ?? error.message;
}
