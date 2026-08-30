import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { StrictMode } from "react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "./App";
import { cachedLeaderboard } from "./lib/backend";
import { LEGAL_CONSENT_KEY, LEGAL_VERSION } from "./lib/legal";

const trackMock = vi.hoisted(() => vi.fn());

vi.mock("@vercel/analytics", () => ({ track: trackMock }));

vi.mock("@vercel/analytics/react", () => ({
  Analytics: () => <div data-testid="vercel-analytics" />
}));

function renderApp(path = "/") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(<QueryClientProvider client={queryClient}><MemoryRouter initialEntries={[path]}><App /></MemoryRouter></QueryClientProvider>);
}

function renderStrictApp(path = "/") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(<StrictMode><QueryClientProvider client={queryClient}><MemoryRouter initialEntries={[path]}><App /></MemoryRouter></QueryClientProvider></StrictMode>);
}

function acceptCurrentLegalTerms() {
  localStorage.setItem(LEGAL_CONSENT_KEY, JSON.stringify({
    version: LEGAL_VERSION,
    acceptedAt: "2026-08-30T12:00:00.000Z"
  }));
}

describe("YEET web experience", () => {
  beforeEach(() => trackMock.mockClear());

  it("mounts Vercel Web Analytics at the app root", () => {
    renderApp();
    expect(screen.getByTestId("vercel-analytics")).toBeInTheDocument();
  });

  it("discards the retired leaderboard cache containing seeded accounts", () => {
    localStorage.setItem("yeet.leaderboard.v1", JSON.stringify({ leaders: [{ handle: "seeded" }] }));
    expect(cachedLeaderboard()).toBeUndefined();
    expect(localStorage.getItem("yeet.leaderboard.v1")).toBeNull();
  });

  it("requires an adult safety acknowledgment before first gameplay", async () => {
    const user = userEvent.setup();
    renderApp();
    expect(screen.getByText("TAP → YEET → CATCH")).toBeInTheDocument();
    expect(screen.getByText("THROWING A PHONE CAN BE DANGEROUS.")).toBeInTheDocument();
    expect(screen.getByText(/serious injury, or death/i)).toBeInTheDocument();
    const continueButton = screen.getByRole("button", { name: "I AGREE — LET’S YEET" });
    const acknowledgment = screen.getByRole("checkbox", { name: /I am 18 or older/i });
    expect(continueButton).toBeDisabled();
    await user.tab();
    expect(acknowledgment).toHaveFocus();
    await user.keyboard(" ");
    expect(acknowledgment).toBeChecked();
    expect(continueButton).toBeEnabled();
    await user.click(continueButton);
    expect(screen.getByRole("button", { name: "YEET" })).toBeInTheDocument();
    expect(JSON.parse(localStorage.getItem(LEGAL_CONSENT_KEY) ?? "null")).toMatchObject({ version: LEGAL_VERSION });
    expect(trackMock).toHaveBeenCalledWith("legal_gate_viewed", { reason: "first_visit", version: LEGAL_VERSION });
    expect(trackMock).toHaveBeenCalledWith("legal_accepted", { prior_status: "missing", version: LEGAL_VERSION });
  });

  it("does not duplicate the legal gate event under Strict Mode", () => {
    renderStrictApp();
    expect(trackMock.mock.calls.filter(([name]) => name === "legal_gate_viewed")).toHaveLength(1);
  });

  it("requires new consent from existing users and after a legal version change", () => {
    localStorage.setItem("yeet.tutorial.complete", "true");
    localStorage.setItem(LEGAL_CONSENT_KEY, JSON.stringify({ version: "2026-08-29", acceptedAt: "2026-08-29T12:00:00.000Z" }));
    renderApp();
    expect(screen.getByRole("button", { name: "I AGREE — LET’S YEET" })).toBeDisabled();
    expect(trackMock).toHaveBeenCalledWith("legal_gate_viewed", { reason: "version_update", version: LEGAL_VERSION });
  });

  it("replays the tutorial without erasing or repeating accepted consent", async () => {
    acceptCurrentLegalTerms();
    renderApp();
    await userEvent.click(screen.getByRole("button", { name: "Open settings" }));
    await userEvent.click(screen.getByText("REPLAY TUTORIAL"));
    expect(screen.queryByRole("checkbox", { name: /I am 18 or older/i })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "BACK TO YEET" }));
    expect(screen.getByRole("button", { name: "YEET" })).toBeInTheDocument();
    expect(JSON.parse(localStorage.getItem(LEGAL_CONSENT_KEY) ?? "null")).toMatchObject({ version: LEGAL_VERSION });
    expect(trackMock).toHaveBeenCalledWith("tutorial_replay_viewed", { account_state: "guest" });
    expect(trackMock).toHaveBeenCalledWith("tutorial_replay_completed", { account_state: "guest" });
  });

  it("opens the complete guest home and account flow", async () => {
    acceptCurrentLegalTerms();
    renderApp();
    expect(screen.getByRole("button", { name: "YEET" })).toBeInTheDocument();
    expect(screen.getByText("LEADERBOARD UNAVAILABLE")).toBeInTheDocument();
    await userEvent.click(screen.getByText("PLAY AS GUEST"));
    expect(screen.getByText("SAVE YOUR SCORES")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /CONTINUE WITH GOOGLE/ })).toBeDisabled();
    expect(screen.getByRole("button", { name: "EMAIL ME A MAGIC LINK" })).toBeDisabled();
    expect(screen.queryByText(/SIX-DIGIT CODE/)).not.toBeInTheDocument();
  });

  it("keeps settings on the right and removes the header leaderboard button", () => {
    acceptCurrentLegalTerms();
    renderApp();
    expect(screen.getByRole("button", { name: "Open settings" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Open leaderboard" })).not.toBeInTheDocument();
  });

  it("shows a clear invalid state when motion samples are unavailable", async () => {
    acceptCurrentLegalTerms();
    renderApp();
    await userEvent.click(screen.getByRole("button", { name: "YEET" }));
    expect(await screen.findByText("3")).toBeInTheDocument();
    expect(screen.getByText("HOLD STILL")).toBeInTheDocument();
    expect(await screen.findByText("NO YEET")).toBeInTheDocument();
    expect(screen.getByText(/sample rate is not reliable/i)).toBeInTheDocument();
    expect(trackMock).toHaveBeenCalledWith("yeet_started", { account_state: "guest", pov_requested: false });
    expect(trackMock).toHaveBeenCalledWith("yeet_invalid", { account_state: "guest", reason: "preflight_unreliable" });
  });

  it("loads privacy and terms directly through router routes", () => {
    const privacy = renderApp("/privacy");
    expect(screen.getByRole("heading", { name: "PRIVACY NOTICE" })).toBeInTheDocument();
    expect(screen.getByText(/Vercel Web Analytics begins when the app loads/i)).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "ANONYMOUS INTERACTION EVENTS" })).toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "support@yeetphone.com" })[0]).toHaveAttribute(
      "href",
      "mailto:support@yeetphone.com",
    );
    privacy.unmount();
    renderApp("/terms");
    expect(screen.getByRole("heading", { name: "TERMS OF USE" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "18+ ONLY" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "RELEASE OF ORDINARY-NEGLIGENCE CLAIMS" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "PRIVACY, ANALYTICS, AND PROVIDERS" })).toBeInTheDocument();
    expect(screen.getByText(/Vercel Web Analytics for anonymous page views and categorical product-interaction events/i)).toBeInTheDocument();
  });

  it("tracks successful PWA installation without event properties", async () => {
    acceptCurrentLegalTerms();
    renderApp();
    window.dispatchEvent(new Event("appinstalled"));
    await waitFor(() => expect(trackMock).toHaveBeenCalledWith("pwa_installed", undefined));
  });

  it("keeps emitted custom events within the two-property limit", async () => {
    acceptCurrentLegalTerms();
    renderApp();
    await userEvent.click(screen.getByRole("button", { name: "Open settings" }));
    await userEvent.click(screen.getByText("ACCOUNT"));
    for (const [, properties] of trackMock.mock.calls) {
      expect(properties == null ? 0 : Object.keys(properties).length).toBeLessThanOrEqual(2);
    }
  });

  it("keeps the POV switch keyboard operable", () => {
    acceptCurrentLegalTerms();
    renderApp();
    const control = screen.getByRole("switch", { name: "Record POV" });
    fireEvent.keyDown(control, { key: " " });
    expect(control).toHaveAttribute("data-state");
  });
});
