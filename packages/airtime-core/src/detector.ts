import {
  type DetectionConfig,
  type DetectionResult,
  type DetectionState,
  type MotionSample,
  SPIKE_V1_CONFIG
} from "./types.ts";

const magnitude = (sample: MotionSample) => Math.hypot(sample.x, sample.y, sample.z);
const finiteSample = (sample: MotionSample) =>
  Number.isFinite(sample.timestamp) && Number.isFinite(sample.x) &&
  Number.isFinite(sample.y) && Number.isFinite(sample.z) && Number.isFinite(magnitude(sample));

export class AirtimeDetector {
  state: DetectionState = { kind: "idle" };
  private firstArmedSampleTimestamp?: number;
  private lastTimestamp?: number;
  private preflightPeakAcceleration = 0;
  private impactPeakAcceleration = 0;
  private airborneSampleCount = 0;

  constructor(private readonly config: DetectionConfig = SPIKE_V1_CONFIG) {}

  arm(): DetectionState {
    this.resetMeasurements();
    return (this.state = { kind: "armed" });
  }

  reset(): DetectionState {
    this.resetMeasurements();
    return (this.state = { kind: "idle" });
  }

  process(sample: MotionSample): DetectionState {
    if (this.state.kind === "idle" || this.isTerminal) return this.state;
    if (!finiteSample(sample)) return this.invalidate("invalid-sample");

    if (this.lastTimestamp !== undefined) {
      if (sample.timestamp <= this.lastTimestamp) return this.invalidate("non-monotonic-timestamp");
      const gap = sample.timestamp - this.lastTimestamp;
      if (gap - this.config.maximumInFlightSampleGap > 1e-9) {
        if (this.state.kind === "airborne" || this.state.kind === "possible-landing") {
          return this.invalidate("sample-gap");
        }
        if (this.state.kind === "possible-airborne") this.state = { kind: "armed" };
      }
    }

    this.lastTimestamp = sample.timestamp;
    this.firstArmedSampleTimestamp ??= sample.timestamp;
    if ((this.state.kind === "armed" || this.state.kind === "possible-airborne") &&
        sample.timestamp - this.firstArmedSampleTimestamp >= this.config.armedTimeout) {
      return this.invalidate("no-throw");
    }

    const g = magnitude(sample);
    switch (this.state.kind) {
      case "armed":
        this.preflightPeakAcceleration = Math.max(this.preflightPeakAcceleration, g);
        if (g <= this.config.airborneEntryMaximumG) {
          this.impactPeakAcceleration = 0;
          this.airborneSampleCount = 1;
          this.state = { kind: "possible-airborne", candidateStart: sample.timestamp, sampleCount: 1 };
        }
        break;
      case "possible-airborne": {
        if (g <= this.config.airborneEntryMaximumG) {
          const nextCount = this.state.sampleCount + 1;
          this.airborneSampleCount += 1;
          if (nextCount >= this.config.airborneConfirmationSamples &&
              sample.timestamp - this.state.candidateStart + 1e-9 >= this.config.airborneConfirmationDuration) {
            this.state = { kind: "airborne", start: this.state.candidateStart };
          } else {
            this.state = { ...this.state, sampleCount: nextCount };
          }
        } else {
          this.impactPeakAcceleration = 0;
          this.airborneSampleCount = 0;
          this.preflightPeakAcceleration = Math.max(this.preflightPeakAcceleration, g);
          this.state = { kind: "armed" };
        }
        break;
      }
      case "airborne":
        this.airborneSampleCount += 1;
        if (g >= this.config.airborneExitMinimumG) {
          this.impactPeakAcceleration = g;
          this.state = { kind: "possible-landing", start: this.state.start, candidateEnd: sample.timestamp, sampleCount: 1 };
        } else if (this.config.maximumAirtime && sample.timestamp - this.state.start > this.config.maximumAirtime) {
          return this.invalidate("exceeded-maximum-airtime");
        }
        break;
      case "possible-landing": {
        this.airborneSampleCount += 1;
        this.impactPeakAcceleration = Math.max(this.impactPeakAcceleration, g);
        if (g >= this.config.airborneExitMinimumG) {
          const nextCount = this.state.sampleCount + 1;
          if (nextCount >= this.config.landingConfirmationSamples &&
              sample.timestamp - this.state.candidateEnd + 1e-9 >= this.config.landingConfirmationDuration) {
            return this.finish(this.state.start, this.state.candidateEnd);
          }
          this.state = { ...this.state, sampleCount: nextCount };
        } else {
          if (this.config.maximumAirtime && sample.timestamp - this.state.start > this.config.maximumAirtime) {
            return this.invalidate("exceeded-maximum-airtime");
          }
          this.impactPeakAcceleration = 0;
          this.state = { kind: "airborne", start: this.state.start };
        }
        break;
      }
    }
    return this.state;
  }

  get isTerminal() {
    return this.state.kind === "finished" || this.state.kind === "invalid";
  }

  private finish(start: number, end: number): DetectionState {
    const airtime = end - start;
    if (airtime < this.config.minimumAirtime) return this.invalidate("too-short");
    if (this.config.maximumAirtime && airtime > this.config.maximumAirtime) {
      return this.invalidate("exceeded-maximum-airtime");
    }
    const result: DetectionResult = {
      airborneStartTimestamp: start,
      landingTimestamp: end,
      airtime,
      preflightPeakAcceleration: this.preflightPeakAcceleration,
      impactPeakAcceleration: this.impactPeakAcceleration,
      airborneSampleCount: this.airborneSampleCount
    };
    return (this.state = { kind: "finished", result });
  }

  private invalidate(reason: Extract<DetectionState, { kind: "invalid" }>["reason"]): DetectionState {
    return (this.state = { kind: "invalid", reason });
  }

  private resetMeasurements() {
    this.firstArmedSampleTimestamp = undefined;
    this.lastTimestamp = undefined;
    this.preflightPeakAcceleration = 0;
    this.impactPeakAcceleration = 0;
    this.airborneSampleCount = 0;
  }
}
