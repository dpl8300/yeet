import { useEffect, useMemo, useState } from "react";
import { Download, Share2 } from "lucide-react";
import { createBrandedVideo, shareOrDownload } from "../lib/pov";
import { Button } from "./ui/Button";
import { Dialog } from "./ui/Dialog";

export function POVDialog({ open, onOpenChange, blob, airtimeMs, rank }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  blob: Blob;
  airtimeMs: number;
  rank?: number;
}) {
  const url = useMemo(() => URL.createObjectURL(blob), [blob]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string>();
  useEffect(() => () => URL.revokeObjectURL(url), [url]);

  const exportVideo = async () => {
    setBusy(true); setMessage("Building your branded video…");
    try {
      const branded = await createBrandedVideo(blob, airtimeMs, rank);
      await shareOrDownload(branded);
      setMessage("Ready to fly.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "The branded export failed.");
    } finally { setBusy(false); }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange} title="YOUR POV" description="The raw recording stays on this device and disappears when you leave.">
      <video className="pov-video" src={url} playsInline controls />
      <Button disabled={busy} onClick={exportVideo}>{typeof navigator.share === "function" ? <Share2 /> : <Download />}{busy ? "PROCESSING…" : "BRAND & SHARE"}</Button>
      {message && <p className="status-message" role="status">{message}</p>}
    </Dialog>
  );
}
