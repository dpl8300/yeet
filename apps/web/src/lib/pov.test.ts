import { afterEach, describe, expect, it, vi } from "vitest";
import { shareVideo, supportsBrandedPovExport, supportsPovRecording } from "./pov";

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
  Reflect.deleteProperty(navigator, "canShare");
  Reflect.deleteProperty(navigator, "share");
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

describe("POV sharing", () => {
  it("shares the video with the YEET title and website link", async () => {
    const canShare = vi.fn(() => true);
    const share = vi.fn(async () => undefined);
    Object.defineProperty(navigator, "canShare", { configurable: true, value: canShare });
    Object.defineProperty(navigator, "share", { configurable: true, value: share });

    const outcome = await shareVideo(new Blob(["video"], { type: "video/mp4" }));

    expect(outcome).toBe("shared");
    expect(canShare).toHaveBeenCalledWith({ files: [expect.any(File)] });
    expect(share).toHaveBeenCalledWith({
      files: [expect.objectContaining({ name: "yeet-flight.mp4", type: "video/mp4" })],
      title: "My YEET",
      text: "How high can you go? https://yeetphone.com"
    });
  });
});
