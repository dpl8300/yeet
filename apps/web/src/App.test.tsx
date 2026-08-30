import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { App } from "./App";

function renderApp(path = "/") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(<QueryClientProvider client={queryClient}><MemoryRouter initialEntries={[path]}><App /></MemoryRouter></QueryClientProvider>);
}

describe("YEET web experience", () => {
  it("starts with the tutorial and safety notice", () => {
    renderApp();
    expect(screen.getByText("TAP → YEET → CATCH")).toBeInTheDocument();
    expect(screen.getByText("YOUR PHONE. YOUR RISK.")).toBeInTheDocument();
  });

  it("opens the complete guest home and account flow", async () => {
    localStorage.setItem("yeet.tutorial.complete", "true");
    renderApp();
    expect(screen.getByRole("button", { name: "YEET" })).toBeInTheDocument();
    expect(screen.getByText("LEADERBOARD UNAVAILABLE")).toBeInTheDocument();
    await userEvent.click(screen.getByText("PLAY AS GUEST"));
    expect(screen.getByText("SAVE YOUR SCORES")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /CONTINUE WITH GOOGLE/ })).toBeDisabled();
  });

  it("keeps settings on the right and removes the header leaderboard button", () => {
    localStorage.setItem("yeet.tutorial.complete", "true");
    renderApp();
    expect(screen.getByRole("button", { name: "Open settings" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Open leaderboard" })).not.toBeInTheDocument();
  });

  it("shows a clear invalid state when motion samples are unavailable", async () => {
    localStorage.setItem("yeet.tutorial.complete", "true");
    renderApp();
    await userEvent.click(screen.getByRole("button", { name: "YEET" }));
    expect(await screen.findByText("3")).toBeInTheDocument();
    expect(screen.getByText("HOLD STILL")).toBeInTheDocument();
    expect(await screen.findByText("NO YEET")).toBeInTheDocument();
    expect(screen.getByText(/sample rate is not reliable/i)).toBeInTheDocument();
  });

  it("loads privacy and terms directly through router routes", () => {
    const privacy = renderApp("/privacy");
    expect(screen.getByRole("heading", { name: "PRIVACY" })).toBeInTheDocument();
    privacy.unmount();
    renderApp("/terms");
    expect(screen.getByRole("heading", { name: "TERMS" })).toBeInTheDocument();
  });

  it("keeps the POV switch keyboard operable", () => {
    localStorage.setItem("yeet.tutorial.complete", "true");
    renderApp();
    const control = screen.getByRole("switch", { name: "Record POV" });
    fireEvent.keyDown(control, { key: " " });
    expect(control).toHaveAttribute("data-state");
  });
});
