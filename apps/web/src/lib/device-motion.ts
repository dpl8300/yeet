import {
  type MotionSample,
  type PreflightResult,
  type RawTraceSample,
  validatePreflight
} from "@yeet/airtime-core";

type PermissionedDeviceMotionEvent = typeof DeviceMotionEvent & {
  requestPermission?: () => Promise<"granted" | "denied">;
};

export type PlayMode = "ranked" | "view-only";

export function motionCapability(): PlayMode {
  if (!("DeviceMotionEvent" in window)) return "view-only";
  return "ranked";
}

export async function requestMotionPermission() {
  const constructor = DeviceMotionEvent as PermissionedDeviceMotionEvent;
  if (typeof constructor.requestPermission === "function") {
    if (await constructor.requestPermission() !== "granted") throw new Error("motion-permission-denied");
  }
}

function parseEvent(event: DeviceMotionEvent): { motion: MotionSample; raw: RawTraceSample } | undefined {
  const acceleration = event.accelerationIncludingGravity;
  if (acceleration?.x == null || acceleration.y == null || acceleration.z == null) return undefined;
  const timestamp = performance.now();
  return {
    motion: {
      timestamp: timestamp / 1000,
      x: acceleration.x / 9.80665,
      y: acceleration.y / 9.80665,
      z: acceleration.z / 9.80665
    },
    raw: { t_ms: timestamp, ax_ms2: acceleration.x, ay_ms2: acceleration.y, az_ms2: acceleration.z }
  };
}

export async function runStationaryPreflight(durationMs = 500): Promise<PreflightResult> {
  const samples: MotionSample[] = [];
  const listener = (event: DeviceMotionEvent) => {
    const sample = parseEvent(event);
    if (sample) samples.push(sample.motion);
  };
  window.addEventListener("devicemotion", listener);
  await new Promise((resolve) => window.setTimeout(resolve, durationMs));
  window.removeEventListener("devicemotion", listener);
  return validatePreflight(samples);
}

export function listenForMotion(onSample: (motion: MotionSample, raw: RawTraceSample) => void) {
  const listener = (event: DeviceMotionEvent) => {
    const sample = parseEvent(event);
    if (sample) onSample(sample.motion, sample.raw);
  };
  window.addEventListener("devicemotion", listener);
  return () => window.removeEventListener("devicemotion", listener);
}

export async function requestWakeLock() {
  if (!("wakeLock" in navigator)) return undefined;
  try {
    return await (navigator as Navigator & { wakeLock: { request: (type: "screen") => Promise<{ release: () => Promise<void> }> } }).wakeLock.request("screen");
  } catch { return undefined; }
}
