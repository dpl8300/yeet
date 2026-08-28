import { describe, expect, it } from "vitest";
import fixture from "./fixtures/golden-traces.json";
import { AirtimeDetector, validateAndDetectTrace, validatePreflight } from "../src";

describe("AirtimeDetector", () => {
  it("excludes entry and landing confirmation latency", () => {
    const result = validateAndDetectTrace(fixture.valid);
    expect(Math.round(result.airtime * 1000)).toBe(fixture.expectedAirtimeMs);
    expect(Math.round(result.airborneStartTimestamp * 1000)).toBe(20);
    expect(Math.round(result.landingTimestamp * 1000)).toBe(250);
  });

  it("rejects non-monotonic timestamps", () => {
    const trace = [...fixture.valid];
    trace[4] = { ...trace[4], t_ms: trace[3].t_ms };
    expect(() => validateAndDetectTrace(trace)).toThrow("non-monotonic-timestamp");
  });

  it("rejects an in-flight sample gap over 50ms", () => {
    const detector = new AirtimeDetector();
    detector.arm();
    [0, .01, .02, .03].forEach((timestamp) => detector.process({ timestamp, x: 0, y: 0, z: .1 }));
    detector.process({ timestamp: .09, x: 0, y: 0, z: .1 });
    expect(detector.state).toEqual({ kind: "invalid", reason: "sample-gap" });
  });

  it("requires a calibrated, reliable 500ms preflight", () => {
    const samples = Array.from({ length: 26 }, (_, index) => ({ timestamp: index * .02, x: 0, y: 0, z: 1 }));
    expect(validatePreflight(samples)).toMatchObject({ ok: true, sampleCount: 26 });
    expect(validatePreflight(samples.slice(0, 19))).toEqual({ ok: false, reason: "not-enough-samples" });
  });

  it("keeps stationary samples armed", () => {
    const detector = armed();
    for (let index = 0; index < 100; index += 1) detector.process(sample(index * .01, 1));
    expect(detector.state).toEqual({ kind: "armed" });
  });

  it("uses vector magnitude rather than a changing axis", () => {
    const detector = armed();
    detector.process({ timestamp: 0, x: 1, y: 0, z: 0 });
    detector.process({ timestamp: .01, x: 0, y: -1, z: 0 });
    detector.process({ timestamp: .02, x: 0, y: 0, z: 1 });
    detector.process({ timestamp: .03, x: -1, y: 0, z: 0 });
    expect(detector.state).toEqual({ kind: "armed" });
  });

  it("returns a brief low-g sequence to armed", () => {
    const detector = armed();
    detector.process(sample(0, 1));
    [.01, .02, .03].forEach((timestamp) => detector.process(sample(timestamp, .1)));
    detector.process(sample(.04, 1));
    expect(detector.state).toEqual({ kind: "armed" });
  });

  it("backdates airborne confirmation to the first low-g sample", () => {
    const detector = armed();
    detector.process(sample(1, 1));
    [1.01, 1.02, 1.03, 1.04].forEach((timestamp) => detector.process(sample(timestamp, .1)));
    expect(detector.state).toEqual({ kind: "airborne", start: 1.01 });
  });

  it("keeps hysteresis values airborne", () => {
    const detector = airborne(1);
    detector.process(sample(1.04, .3));
    detector.process(sample(1.05, .49));
    expect(detector.state).toEqual({ kind: "airborne", start: 1 });
  });

  it("backdates landing and excludes confirmation delay", () => {
    const detector = airborne(1);
    feedLowG(detector, 4, 19);
    detector.process(sample(1.2, .8));
    detector.process(sample(1.21, .9));
    detector.process(sample(1.22, 1));
    expect(detector.state.kind).toBe("finished");
    if (detector.state.kind === "finished") {
      expect(detector.state.result.airborneStartTimestamp).toBeCloseTo(1);
      expect(detector.state.result.landingTimestamp).toBeCloseTo(1.2);
      expect(detector.state.result.airtime).toBeCloseTo(.2);
    }
  });

  it("does not finish on one landing spike", () => {
    const detector = airborne(1);
    feedLowG(detector, 4, 9);
    detector.process(sample(1.1, 1.8));
    detector.process(sample(1.11, .1));
    expect(detector.state).toEqual({ kind: "airborne", start: 1 });
  });

  it("finishes a gradual soft catch", () => {
    const detector = airborne(1);
    feedLowG(detector, 4, 19);
    detector.process(sample(1.2, .5));
    detector.process(sample(1.21, .65));
    detector.process(sample(1.22, .8));
    expect(detector.state.kind).toBe("finished");
  });

  it("rejects too-short airtime", () => {
    const detector = airborne(1);
    feedLowG(detector, 4, 9);
    detector.process(sample(1.1, .8));
    detector.process(sample(1.11, .9));
    detector.process(sample(1.12, 1));
    expect(detector.state).toEqual({ kind: "invalid", reason: "too-short" });
  });

  it("times out a no-throw using sensor timestamps", () => {
    const detector = armed();
    detector.process(sample(10, 1));
    detector.process(sample(25, 1));
    expect(detector.state).toEqual({ kind: "invalid", reason: "no-throw" });
  });

  it("accepts airtime longer than three seconds", () => {
    const detector = airborne(1);
    for (let index = 1; index <= 100; index += 1) detector.process(sample(1.03 + index * .04, .1));
    detector.process(sample(5.04, .8));
    detector.process(sample(5.05, .9));
    detector.process(sample(5.06, 1));
    expect(detector.state.kind).toBe("finished");
    if (detector.state.kind === "finished") expect(detector.state.result.airtime).toBeGreaterThan(3);
  });

  it("rejects a non-finite sample", () => {
    const detector = armed();
    detector.process({ timestamp: 1, x: Number.NaN, y: 0, z: 0 });
    expect(detector.state).toEqual({ kind: "invalid", reason: "invalid-sample" });
  });

  it("clears candidates and timestamps on reset", () => {
    const detector = airborne(1);
    detector.reset();
    detector.arm();
    detector.process(sample(.5, 1));
    expect(detector.state).toEqual({ kind: "armed" });
  });
});

function sample(timestamp: number, value: number) {
  return { timestamp, x: value, y: 0, z: 0 };
}

function armed() {
  const detector = new AirtimeDetector();
  detector.arm();
  return detector;
}

function airborne(start: number) {
  const detector = armed();
  [start, start + .01, start + .02, start + .03].forEach((timestamp) => detector.process(sample(timestamp, .1)));
  return detector;
}

function feedLowG(detector: AirtimeDetector, firstHundredth: number, lastHundredth: number) {
  for (let hundredth = firstHundredth; hundredth <= lastHundredth; hundredth += 1) {
    detector.process(sample(1 + hundredth / 100, .1));
  }
}
