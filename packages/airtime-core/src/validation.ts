import { AirtimeDetector } from "./detector.ts";
import {
  type DetectionResult,
  type MotionSample,
  type PreflightResult,
  type RawTraceSample,
  STANDARD_GRAVITY_MS2
} from "./types.ts";

function percentile(sorted: number[], p: number) {
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * p) - 1))];
}

export function validatePreflight(samples: MotionSample[]): PreflightResult {
  if (samples.length < 20) return { ok: false, reason: "not-enough-samples" };
  const magnitudes: number[] = [];
  const gaps: number[] = [];
  for (let index = 0; index < samples.length; index += 1) {
    const sample = samples[index];
    const value = Math.hypot(sample.x, sample.y, sample.z);
    if (![sample.timestamp, sample.x, sample.y, sample.z, value].every(Number.isFinite)) {
      return { ok: false, reason: "invalid-sample" };
    }
    magnitudes.push(value);
    if (index > 0) {
      const gap = sample.timestamp - samples[index - 1].timestamp;
      if (gap <= 0) return { ok: false, reason: "non-monotonic-timestamp" };
      gaps.push(gap * 1000);
    }
  }
  magnitudes.sort((a, b) => a - b);
  gaps.sort((a, b) => a - b);
  const medianMagnitudeG = (magnitudes[Math.floor((magnitudes.length - 1) / 2)] + magnitudes[Math.ceil((magnitudes.length - 1) / 2)]) / 2;
  const p95GapMs = percentile(gaps, 0.95);
  if (medianMagnitudeG < 0.75 || medianMagnitudeG > 1.25) return { ok: false, reason: "uncalibrated" };
  if (p95GapMs > 50) return { ok: false, reason: "unreliable-sampling" };
  return { ok: true, medianMagnitudeG, p95GapMs, sampleCount: samples.length };
}

export function rawTraceToMotionSamples(samples: RawTraceSample[]): MotionSample[] {
  return samples.map((sample) => ({
    timestamp: sample.t_ms / 1000,
    x: sample.ax_ms2 / STANDARD_GRAVITY_MS2,
    y: sample.ay_ms2 / STANDARD_GRAVITY_MS2,
    z: sample.az_ms2 / STANDARD_GRAVITY_MS2
  }));
}

export function validateAndDetectTrace(samples: RawTraceSample[]): DetectionResult {
  if (samples.length > 2_500) throw new Error("trace-too-large");
  if (samples.length === 0) throw new Error("invalid-terminal-state");
  if (samples.some((sample) => !sample || typeof sample !== "object" ||
      ![sample.t_ms, sample.ax_ms2, sample.ay_ms2, sample.az_ms2].every(Number.isFinite))) {
    throw new Error("invalid-sample");
  }
  if (samples[samples.length - 1].t_ms - samples[0].t_ms > 20_000) throw new Error("trace-too-long");

  const detector = new AirtimeDetector();
  detector.arm();
  for (const sample of rawTraceToMotionSamples(samples)) {
    detector.process(sample);
    if (detector.state.kind === "invalid") throw new Error(detector.state.reason);
    if (detector.state.kind === "finished") return detector.state.result;
  }
  throw new Error("invalid-terminal-state");
}
