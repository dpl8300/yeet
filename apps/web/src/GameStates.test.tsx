import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { GameScreen } from "./pages/YeetExperience";
import { POVDialog } from "./components/POVDialog";

const trackMock = vi.hoisted(() => vi.fn());
vi.mock("@vercel/analytics", () => ({ track: trackMock }));

const noop = () => undefined;
const start = async () => undefined;
function wrap(node: React.ReactNode) {
  return render(<QueryClientProvider client={new QueryClient()}>{node}</QueryClientProvider>);
}

describe("gameplay and result states", () => {
  beforeEach(() => trackMock.mockClear());

  it.each([
    [{ kind: "countdown" as const, value: 3 as const }, "3"],
    [{ kind: "waiting" as const }, "YEET!"],
    [{ kind: "airborne" as const, start: performance.now() / 1000 }, "AIRTIME"]
  ])("renders the expected active phase", (phase, copy) => {
    const view = wrap(<GameScreen phase={phase} start={start} home={noop} session={null} onAccount={noop} />);
    expect(screen.getByText(copy)).toBeInTheDocument();
    view.unmount();
  });

  it("matches the browser chrome color to the active full-screen phase", () => {
    const view = wrap(<GameScreen phase={{ kind: "waiting" }} start={start} home={noop} session={null} onAccount={noop} />);
    expect(document.querySelector<HTMLMetaElement>('meta[name="theme-color"]')?.content).toBe("#ffd108");
    expect(document.documentElement.style.backgroundColor).toBe("rgb(255, 209, 8)");
    view.rerender(<QueryClientProvider client={new QueryClient()}><GameScreen phase={{ kind: "countdown", value: 3 }} start={start} home={noop} session={null} onAccount={noop} /></QueryClientProvider>);
    expect(document.querySelector<HTMLMetaElement>('meta[name="theme-color"]')?.content).toBe("#fffef9");
  });

  it("renders retry controls for invalid attempts", () => {
    wrap(<GameScreen phase={{ kind: "invalid", reason: "Sampling failed." }} start={start} home={noop} session={null} onAccount={noop} />);
    expect(screen.getByText("NO YEET")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "TRY AGAIN" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "BACK HOME" })).not.toBeInTheDocument();
  });

  it("tracks an invalid retry as a result action", async () => {
    const retry = vi.fn(async () => undefined);
    wrap(<GameScreen phase={{ kind: "invalid", reason: "Sampling failed." }} start={retry} home={noop} session={null} onAccount={noop} />);
    await userEvent.click(screen.getByRole("button", { name: "TRY AGAIN" }));
    expect(trackMock).toHaveBeenCalledWith("result_action", { account_state: "guest", action: "retry_invalid" });
    expect(retry).toHaveBeenCalledOnce();
  });

  it("keeps browser preparation failures escapable", () => {
    wrap(<GameScreen phase={{ kind: "invalid", reason: "Motion access was denied.", canGoHome: true }} start={start} home={noop} session={null} onAccount={noop} />);
    expect(screen.getByRole("button", { name: "BACK HOME" })).toBeInTheDocument();
  });

  it("shows a catch celebration before a valid result", async () => {
    wrap(<GameScreen phase={{ kind: "caught", attempt: {
      id: "00000000-0000-4000-8000-000000000001",
      result: { airborneStartTimestamp: 1, landingTimestamp: 1.5, airtime: .5, preflightPeakAcceleration: 1, impactPeakAcceleration: 1.2, airborneSampleCount: 50 },
      samples: [],
      pov: { kind: "none" }
    } }} start={start} home={noop} session={null} onAccount={noop} />);
    expect(screen.getByText("NICE CATCH")).toBeInTheDocument();
    expect(await screen.findByText("AIRTIME", {}, { timeout: 2000 })).toBeInTheDocument();
    expect(screen.getByText("0.50")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "BACK HOME" })).toBeInTheDocument();
  });

  it("shows POV finalization without allowing a new throw", async () => {
    wrap(<GameScreen phase={{ kind: "caught", attempt: {
      id: "00000000-0000-4000-8000-000000000002",
      result: { airborneStartTimestamp: 1, landingTimestamp: 1.5, airtime: .5, preflightPeakAcceleration: 1, impactPeakAcceleration: 1.2, airborneSampleCount: 50 },
      samples: [],
      pov: { kind: "finalizing" }
    } }} start={start} home={noop} session={null} onAccount={noop} />);
    expect(await screen.findByRole("button", { name: "PROCESSING POV…" }, { timeout: 2000 })).toBeDisabled();
    expect(screen.getByRole("button", { name: "YEET AGAIN" })).toBeDisabled();
  });

  it("falls back to a raw full-screen share preview when branded export is unavailable", async () => {
    const view = wrap(<POVDialog open onOpenChange={noop} blob={new Blob(["video"], { type: "video/webm" })} airtimeMs={500} />);
    expect(screen.getByText("Your POV")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Play POV video" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "SHARE" }));
    expect(await screen.findByText(/original POV/i)).toBeInTheDocument();
    expect(trackMock).toHaveBeenCalledWith("pov_viewed", { account_state: "guest", result_kind: "normal" });
    expect(trackMock).toHaveBeenCalledWith("pov_export_started", { account_state: "guest", format: "raw" });
    expect(trackMock).toHaveBeenCalledWith("pov_export_result", { outcome: "success", format: "raw" });
    expect(screen.getByRole("button", { name: "SAVE OR SHARE" })).toBeInTheDocument();
    const preview = view.container.ownerDocument.querySelector<HTMLVideoElement>(".pov-share-preview");
    expect(preview).not.toHaveAttribute("controls");
    expect(preview).toHaveAttribute("loop");
    expect(preview?.muted).toBe(true);
  });
});
