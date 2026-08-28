export const STANDARD_GRAVITY_MS2 = 9.80665;

export type MotionSample = {
  timestamp: number;
  x: number;
  y: number;
  z: number;
};

export type RawTraceSample = {
  t_ms: number;
  ax_ms2: number;
  ay_ms2: number;
  az_ms2: number;
};

export type DetectionResult = {
  airborneStartTimestamp: number;
  landingTimestamp: number;
  airtime: number;
  preflightPeakAcceleration: number;
  impactPeakAcceleration: number;
  airborneSampleCount: number;
};

export type InvalidReason =
  | "no-throw"
  | "too-short"
  | "exceeded-maximum-airtime"
  | "sample-gap"
  | "non-monotonic-timestamp"
  | "invalid-sample"
  | "invalid-terminal-state"
  | "trace-too-large"
  | "trace-too-long";

export type DetectionState =
  | { kind: "idle" }
  | { kind: "armed" }
  | { kind: "possible-airborne"; candidateStart: number; sampleCount: number }
  | { kind: "airborne"; start: number }
  | { kind: "possible-landing"; start: number; candidateEnd: number; sampleCount: number }
  | { kind: "finished"; result: DetectionResult }
  | { kind: "invalid"; reason: InvalidReason };

export type DetectionConfig = {
  requestedSampleInterval: number;
  airborneEntryMaximumG: number;
  airborneConfirmationSamples: number;
  airborneConfirmationDuration: number;
  airborneExitMinimumG: number;
  landingConfirmationSamples: number;
  landingConfirmationDuration: number;
  minimumAirtime: number;
  maximumAirtime?: number;
  armedTimeout: number;
  maximumInFlightSampleGap: number;
};

export const SPIKE_V1_CONFIG: Readonly<DetectionConfig> = {
  requestedSampleInterval: 0.01,
  airborneEntryMaximumG: 0.25,
  airborneConfirmationSamples: 4,
  airborneConfirmationDuration: 0.03,
  airborneExitMinimumG: 0.5,
  landingConfirmationSamples: 3,
  landingConfirmationDuration: 0.02,
  minimumAirtime: 0.12,
  armedTimeout: 15,
  maximumInFlightSampleGap: 0.05
};

export type PreflightResult =
  | { ok: true; medianMagnitudeG: number; p95GapMs: number; sampleCount: number }
  | { ok: false; reason: "not-enough-samples" | "invalid-sample" | "non-monotonic-timestamp" | "uncalibrated" | "unreliable-sampling" };
