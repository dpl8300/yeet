import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  accountState,
  airtimeBucket,
  classifyAnalyticsError,
  rankBucket,
  redactAnalyticsUrl,
  trackEvent
} from "./analytics";

const trackMock = vi.hoisted(() => vi.fn());
vi.mock("@vercel/analytics", () => ({ track: trackMock }));

describe("anonymous analytics helpers", () => {
  beforeEach(() => trackMock.mockClear());

  it("derives only categorical account states", () => {
    expect(accountState(null, undefined)).toBe("guest");
    expect(accountState({ user: {} }, undefined, false)).toBe("signed_in_unknown");
    expect(accountState({ user: {} }, null)).toBe("signed_in_no_handle");
    expect(accountState({ user: {} }, { airtime_ms: null })).toBe("signed_in_no_score");
    expect(accountState({ user: {} }, { airtime_ms: 502 })).toBe("signed_in_scored");
  });

  it("uses stable coarse airtime and rank buckets", () => {
    expect([249, 250, 500, 750, 1_000, 1_500].map(airtimeBucket)).toEqual([
      "under_0_25s", "0_25_0_49s", "0_50_0_74s", "0_75_0_99s", "1_00_1_49s", "1_50s_plus"
    ]);
    expect([null, 1, 10, 100, 1_000, 1_001].map(rankBucket)).toEqual([
      "none", "rank_1", "rank_2_10", "rank_11_100", "rank_101_1000", "rank_1001_plus"
    ]);
  });

  it("removes authentication codes, other queries, and fragments from analytics URLs", () => {
    const redacted = redactAnalyticsUrl({
      url: "https://yeetphone.com/auth/callback?code=secret-code&utm_source=private#token",
      type: "pageview"
    });
    expect(redacted).toEqual({ url: "https://yeetphone.com/auth/callback", type: "pageview" });
  });

  it("converts provider failures to allowlisted categories without leaking details", () => {
    const sensitiveError = new Error("Failed to fetch for private@example.com user 00000000-0000-4000-8000-000000000001");
    const reason = classifyAnalyticsError(sensitiveError);
    trackEvent("auth_failed", { method: "email", reason });
    expect(reason).toBe("network");
    const payload = JSON.stringify(trackMock.mock.calls);
    expect(payload).not.toContain("private@example.com");
    expect(payload).not.toContain("00000000-0000-4000-8000-000000000001");
    expect(payload).not.toContain("Failed to fetch");
  });

  it("passes no more than two scalar properties to Vercel", () => {
    trackEvent("yeet_completed", { account_state: "guest", airtime_bucket: "0_50_0_74s" });
    trackEvent("pwa_installed");
    expect(trackMock).toHaveBeenNthCalledWith(1, "yeet_completed", {
      account_state: "guest",
      airtime_bucket: "0_50_0_74s"
    });
    expect(trackMock).toHaveBeenNthCalledWith(2, "pwa_installed", undefined);
    for (const [, properties] of trackMock.mock.calls) {
      expect(properties == null ? 0 : Object.keys(properties).length).toBeLessThanOrEqual(2);
      expect(Object.values(properties ?? {}).every((value) => ["string", "number", "boolean"].includes(typeof value) || value === null)).toBe(true);
    }
  });
});
