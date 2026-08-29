import { afterEach, describe, expect, it } from "vitest";
import { supportsBrandedPovExport, supportsPovRecording } from "./pov";

function enableRecordingApis() {
  Object.defineProperty(navigator, "mediaDevices", {
    configurable: true,
    value: { getUserMedia: async () => undefined }
  });
  Object.defineProperty(window, "MediaRecorder", {
    configurable: true,
    value: class MediaRecorderMock {}
  });
}

afterEach(() => {
  Reflect.deleteProperty(navigator, "mediaDevices");
  Reflect.deleteProperty(window, "MediaRecorder");
  Reflect.deleteProperty(window, "AudioContext");
  Reflect.deleteProperty(HTMLCanvasElement.prototype, "captureStream");
  Reflect.deleteProperty(HTMLVideoElement.prototype, "captureStream");
});

describe("POV browser capabilities", () => {
  it("allows camera recording without canvas or video-element capture", () => {
    enableRecordingApis();

    expect(supportsPovRecording()).toBe(true);
    expect(supportsBrandedPovExport()).toBe(false);
  });

  it("supports branded export with canvas capture and Web Audio routing", () => {
    enableRecordingApis();
    Object.defineProperty(HTMLCanvasElement.prototype, "captureStream", {
      configurable: true,
      value: () => undefined
    });
    Object.defineProperty(window, "AudioContext", {
      configurable: true,
      value: class AudioContextMock {
        createMediaElementSource() {}
        createMediaStreamDestination() {}
      }
    });

    expect(supportsBrandedPovExport()).toBe(true);
  });
});
