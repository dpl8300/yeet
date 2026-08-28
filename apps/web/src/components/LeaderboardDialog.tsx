import { Trophy } from "lucide-react";
import type { LeaderboardSnapshot } from "../lib/backend";
import { formatSeconds } from "../lib/utils";
import { Dialog } from "./ui/Dialog";

export function LeaderboardDialog({ open, onOpenChange, snapshot, stale, error }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  snapshot?: LeaderboardSnapshot;
  stale?: boolean;
  error?: string;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange} title="WORLD LEADERS" description="Best verified browser airtimes.">
      <div className="full-leaderboard">
        {error && <p className="status-message warning">{snapshot ? "Showing the last saved snapshot. " : ""}{error}</p>}
        {stale && !error && <p className="status-message">Refreshing scores…</p>}
        {!snapshot?.leaders.length && <div className="empty-state"><Trophy /><b>NO SCORES YET</b><span>Be the first to claim the board.</span></div>}
        {snapshot?.leaders.map((entry) => (
          <div className="leader-row leader-row-large" key={entry.user_id}>
            <strong>{String(entry.rank).padStart(2, "0")}</strong>
            <span>@{entry.handle}</span>
            <b>{formatSeconds(entry.airtime_ms)}</b>
          </div>
        ))}
        {snapshot?.current_user && (
          <div className="your-ranking">
            <span>YOUR BEST</span><b>#{snapshot.current_user.rank ?? "—"} · {formatSeconds(snapshot.current_user.airtime_ms)}</b>
          </div>
        )}
        <p className="fine-print">Casual social rankings. Sensor measurements are not hardware-attested.</p>
      </div>
    </Dialog>
  );
}
