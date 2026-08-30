import { render, waitFor } from "@testing-library/react";
import { StrictMode } from "react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AuthCallback } from "./AuthCallback";

const mocks = vi.hoisted(() => ({
  track: vi.fn(),
  getSession: vi.fn(),
  exchangeCodeForSession: vi.fn()
}));

vi.mock("@vercel/analytics", () => ({ track: mocks.track }));
vi.mock("../lib/supabase", () => ({
  supabase: {
    auth: {
      getSession: mocks.getSession,
      exchangeCodeForSession: mocks.exchangeCodeForSession
    }
  }
}));

const googleSession = {
  user: { app_metadata: { provider: "google" } }
};

describe("auth callback analytics", () => {
  beforeEach(() => {
    mocks.track.mockClear();
    mocks.getSession.mockReset();
    mocks.exchangeCodeForSession.mockReset();
    window.history.replaceState({}, "", "/");
  });

  it("tracks one successful existing callback session under Strict Mode", async () => {
    mocks.getSession.mockResolvedValue({ data: { session: googleSession }, error: null });
    render(<StrictMode><MemoryRouter><AuthCallback /></MemoryRouter></StrictMode>);
    await waitFor(() => expect(mocks.track).toHaveBeenCalledWith("auth_succeeded", {
      method: "google",
      callback_state: "existing_session"
    }));
    expect(mocks.track.mock.calls.filter(([name]) => name === "auth_succeeded")).toHaveLength(1);
  });

  it("tracks code exchange without including the callback code", async () => {
    window.history.replaceState({}, "", "/auth/callback?code=private-auth-code");
    mocks.getSession.mockResolvedValue({ data: { session: null }, error: null });
    mocks.exchangeCodeForSession.mockResolvedValue({ data: { session: googleSession }, error: null });
    render(<MemoryRouter><AuthCallback /></MemoryRouter>);
    await waitFor(() => expect(mocks.exchangeCodeForSession).toHaveBeenCalledWith("private-auth-code"));
    expect(mocks.track).toHaveBeenCalledWith("auth_succeeded", { method: "google", callback_state: "code_exchange" });
    expect(JSON.stringify(mocks.track.mock.calls)).not.toContain("private-auth-code");
  });
});
