import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { GameScreen } from "./pages/YeetExperience";
import { POVDialog } from "./components/POVDialog";

const noop = () => undefined;
const start = async () => undefined;
function wrap(node: React.ReactNode) {
  return render(<QueryClientProvider client={new QueryClient()}>{node}</QueryClientProvider>);
}

describe("gameplay and result states", () => {
  it.each([
    [{ kind: "preflight" as const }, "HOLD STILL"],
    [{ kind: "countdown" as const, value: 3 as const }, "3"],
    [{ kind: "waiting" as const }, "YEET"],
    [{ kind: "airborne" as const, start: performance.now() / 1000 }, "AIRBORNE"]
  ])("renders the expected active phase", (phase, copy) => {
    const view = wrap(<GameScreen phase={phase} start={start} home={noop} session={null} onAccount={noop} />);
    expect(screen.getByText(copy)).toBeInTheDocument();
    view.unmount();
  });

  it("renders retry controls for invalid attempts", () => {
    wrap(<GameScreen phase={{ kind: "invalid", reason: "Sampling failed." }} start={start} home={noop} session={null} onAccount={noop} />);
    expect(screen.getByText("NO SCORE")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "TRY AGAIN" })).toBeInTheDocument();
  });

  it("shows a catch celebration before a valid result", async () => {
    wrap(<GameScreen phase={{ kind: "caught", attempt: {
      id: "00000000-0000-4000-8000-000000000001",
      result: { airborneStartTimestamp: 1, landingTimestamp: 1.5, airtime: .5, preflightPeakAcceleration: 1, impactPeakAcceleration: 1.2, airborneSampleCount: 50 },
      samples: []
    } }} start={start} home={noop} session={null} onAccount={noop} />);
    expect(screen.getByText("CAUGHT!")).toBeInTheDocument();
    expect(await screen.findByText("VALID FLIGHT", {}, { timeout: 1200 })).toBeInTheDocument();
    expect(screen.getByText("0.50")).toBeInTheDocument();
  });

  it("falls back to sharing the raw device-local POV when branded export is unavailable", () => {
    wrap(<POVDialog open onOpenChange={noop} blob={new Blob(["video"], { type: "video/webm" })} airtimeMs={500} />);
    expect(screen.getByText("YOUR POV")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /SHARE POV/ })).toBeInTheDocument();
  });
});
