import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";
import { App } from "./App";
import { cachedLeaderboard } from "./lib/backend";
import { LEGAL_CONSENT_KEY, LEGAL_VERSION } from "./lib/legal";

vi.mock("@vercel/analytics/react", () => ({
  Analytics: () => <div data-testid="vercel-analytics" />
}));

function renderApp(path = "/") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(<QueryClientProvider client={queryClient}><MemoryRouter initialEntries={[path]}><App /></MemoryRouter></QueryClientProvider>);
}

function acceptCurrentLegalTerms() {
  localStorage.setItem(LEGAL_CONSENT_KEY, JSON.stringify({
    version: LEGAL_VERSION,
    acceptedAt: "2026-08-30T12:00:00.000Z"
  }));
}

describe("YEET web experience", () => {
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
  });

  it("requires new consent from existing users and after a legal version change", () => {
    localStorage.setItem("yeet.tutorial.complete", "true");
    localStorage.setItem(LEGAL_CONSENT_KEY, JSON.stringify({ version: "2026-08-29", acceptedAt: "2026-08-29T12:00:00.000Z" }));
    renderApp();
    expect(screen.getByRole("button", { name: "I AGREE — LET’S YEET" })).toBeDisabled();
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
  });

  it("loads privacy and terms directly through router routes", () => {
    const privacy = renderApp("/privacy");
    expect(screen.getByRole("heading", { name: "PRIVACY NOTICE" })).toBeInTheDocument();
    expect(screen.getByText(/Vercel Web Analytics records anonymous page views/i)).toBeInTheDocument();
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
    expect(screen.getByText(/Vercel Web Analytics to understand aggregated site traffic/i)).toBeInTheDocument();
  });

  it("keeps the POV switch keyboard operable", () => {
    acceptCurrentLegalTerms();
    renderApp();
    const control = screen.getByRole("switch", { name: "Record POV" });
    fireEvent.keyDown(control, { key: " " });
    expect(control).toHaveAttribute("data-state");
  });
});
