import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { Session } from "@supabase/supabase-js";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AccountDialog } from "./AccountDialog";

const mocks = vi.hoisted(() => ({
  track: vi.fn(),
  sendEmailMagicLink: vi.fn(async () => undefined),
  signInWithGoogle: vi.fn(async () => undefined),
  setHandle: vi.fn(async () => ({ id: "ignored", handle: "new_handle" })),
  deleteAccount: vi.fn(async () => undefined),
  signOut: vi.fn(async () => ({ error: null }))
}));

vi.mock("@vercel/analytics", () => ({ track: mocks.track }));
vi.mock("../lib/backend", () => ({
  isSupabaseConfigured: true,
  sendEmailMagicLink: mocks.sendEmailMagicLink,
  signInWithGoogle: mocks.signInWithGoogle,
  setHandle: mocks.setHandle,
  deleteAccount: mocks.deleteAccount
}));
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { signOut: mocks.signOut } }
}));

function session(): Session {
  return {
    user: {
      id: "00000000-0000-4000-8000-000000000001",
      email: "private@example.com",
      last_sign_in_at: new Date().toISOString(),
      app_metadata: {},
      user_metadata: {},
      aud: "authenticated",
      created_at: new Date().toISOString()
    }
  } as Session;
}

describe("account analytics", () => {
  beforeEach(() => {
    for (const mock of Object.values(mocks)) mock.mockClear();
  });

  it("tracks email sign-in intent and link delivery without the email value", async () => {
    render(<AccountDialog open onOpenChange={vi.fn()} session={null} source="result" onChanged={vi.fn()} />);
    await userEvent.type(screen.getByLabelText("EMAIL"), "private@example.com");
    await userEvent.click(screen.getByRole("button", { name: "EMAIL ME A MAGIC LINK" }));
    await waitFor(() => expect(mocks.sendEmailMagicLink).toHaveBeenCalledWith("private@example.com"));
    expect(mocks.track).toHaveBeenCalledWith("auth_started", { method: "email", source: "result" });
    expect(mocks.track).toHaveBeenCalledWith("auth_link_sent", { purpose: "sign_in", source: "result" });
    expect(JSON.stringify(mocks.track.mock.calls)).not.toContain("private@example.com");
  });

  it("tracks handle creation by outcome without the handle", async () => {
    render(<AccountDialog open onOpenChange={vi.fn()} session={session()} source="settings" onChanged={vi.fn()} />);
    await userEvent.type(screen.getByLabelText("HANDLE"), "new_handle");
    await userEvent.click(screen.getByRole("button", { name: "CREATE HANDLE" }));
    await waitFor(() => expect(mocks.setHandle).toHaveBeenCalledWith("new_handle"));
    expect(mocks.track).toHaveBeenCalledWith("profile_save_result", { action: "create", outcome: "success" });
    expect(JSON.stringify(mocks.track.mock.calls)).not.toContain("new_handle");
  });

  it("reduces profile failures to a safe allowlisted outcome", async () => {
    mocks.setHandle.mockRejectedValueOnce(new Error("handle_taken for private_handle"));
    render(<AccountDialog open onOpenChange={vi.fn()} session={session()} source="settings" onChanged={vi.fn()} />);
    await userEvent.type(screen.getByLabelText("HANDLE"), "private_handle");
    await userEvent.click(screen.getByRole("button", { name: "CREATE HANDLE" }));
    await waitFor(() => expect(mocks.track).toHaveBeenCalledWith("profile_save_result", { action: "create", outcome: "handle_taken" }));
    expect(JSON.stringify(mocks.track.mock.calls)).not.toContain("private_handle");
  });

  it("tracks the delete prompt and completed deletion without an account ID", async () => {
    render(<AccountDialog open onOpenChange={vi.fn()} session={session()} source="settings" onChanged={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "Delete account" }));
    expect(mocks.track).toHaveBeenCalledWith("account_delete_prompted", { fresh_session: true });
    await userEvent.click(screen.getByRole("button", { name: "DELETE MY ACCOUNT" }));
    await waitFor(() => expect(mocks.deleteAccount).toHaveBeenCalledOnce());
    expect(mocks.track).toHaveBeenCalledWith("account_delete_result", { outcome: "success", reason: "none" });
    expect(JSON.stringify(mocks.track.mock.calls)).not.toContain("00000000-0000-4000-8000-000000000001");
  });
});
