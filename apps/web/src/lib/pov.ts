function supportedMimeType() {
  const candidates = [
    "video/mp4;codecs=avc1.42E01E,mp4a.40.2",
    "video/mp4;codecs=h264,aac",
    "video/webm;codecs=vp9,opus",
    "video/webm;codecs=vp8,opus",
    "video/webm"
  ];
  return candidates.find((candidate) => MediaRecorder.isTypeSupported(candidate));
}

type CaptureVideo = HTMLVideoElement & { captureStream?: (frameRate?: number) => MediaStream };

export function supportsFullPovPipeline() {
  return Boolean(typeof navigator.mediaDevices?.getUserMedia === "function" &&
    typeof window.MediaRecorder === "function" &&
    typeof HTMLCanvasElement.prototype.captureStream === "function" &&
    typeof (HTMLVideoElement.prototype as CaptureVideo).captureStream === "function" &&
    supportedMimeType());
}

export class POVRecorder {
  private stream?: MediaStream;
  private recorder?: MediaRecorder;
  private chunks: Blob[] = [];

  async prepare() {
    if (!supportsFullPovPipeline()) throw new Error("pov-unsupported");
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: "environment" }, width: { ideal: 1080 }, height: { ideal: 1920 } },
      audio: true
    });
  }

  start() {
    if (!this.stream) throw new Error("pov-not-prepared");
    this.chunks = [];
    this.recorder = new MediaRecorder(this.stream, { mimeType: supportedMimeType() });
    this.recorder.ondataavailable = (event) => { if (event.data.size) this.chunks.push(event.data); };
    this.recorder.start(250);
  }

  async stop() {
    const recorder = this.recorder;
    if (!recorder) throw new Error("pov-not-recording");
    return await new Promise<Blob>((resolve, reject) => {
      recorder.onerror = () => reject(new Error("pov-recording-failed"));
      recorder.onstop = () => {
        const blob = new Blob(this.chunks, { type: recorder.mimeType });
        this.stopTracks();
        resolve(blob);
      };
      recorder.stop();
    });
  }

  discard() {
    if (this.recorder?.state === "recording") this.recorder.stop();
    this.chunks = [];
    this.stopTracks();
  }

  private stopTracks() {
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = undefined;
    this.recorder = undefined;
  }
}

export async function createBrandedVideo(raw: Blob, airtimeMs: number, rank?: number) {
  const inputUrl = URL.createObjectURL(raw);
  const video = document.createElement("video") as CaptureVideo;
  video.src = inputUrl;
  video.playsInline = true;
  video.muted = false;
  await new Promise<void>((resolve, reject) => {
    video.onloadedmetadata = () => resolve();
    video.onerror = () => reject(new Error("pov-replay-failed"));
  });

  const canvas = document.createElement("canvas");
  canvas.width = 1080;
  canvas.height = 1920;
  const context = canvas.getContext("2d")!;
  const canvasStream = canvas.captureStream(30);
  const sourceStream = video.captureStream?.();
  sourceStream?.getAudioTracks().forEach((track) => canvasStream.addTrack(track));
  if (!sourceStream || sourceStream.getAudioTracks().length === 0) {
    URL.revokeObjectURL(inputUrl);
    throw new Error("pov-audio-export-unsupported");
  }

  const mimeType = supportedMimeType()!;
  const recorder = new MediaRecorder(canvasStream, { mimeType, videoBitsPerSecond: 8_000_000 });
  const chunks: Blob[] = [];
  recorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
  const complete = new Promise<Blob>((resolve, reject) => {
    recorder.onerror = () => reject(new Error("pov-export-failed"));
    recorder.onstop = () => resolve(new Blob(chunks, { type: mimeType }));
  });

  const draw = () => {
    if (video.ended || video.paused) return;
    const scale = Math.max(canvas.width / video.videoWidth, canvas.height / video.videoHeight);
    const width = video.videoWidth * scale;
    const height = video.videoHeight * scale;
    context.drawImage(video, (canvas.width - width) / 2, (canvas.height - height) / 2, width, height);
    context.fillStyle = "rgba(17,16,13,.78)";
    context.fillRect(42, 48, 996, 190);
    context.fillStyle = "#FFD108";
    context.font = "900 112px Impact, sans-serif";
    context.fillText("YEET", 78, 160);
    context.fillStyle = "white";
    context.font = "800 52px system-ui";
    context.textAlign = "right";
    context.fillText(`${(airtimeMs / 1000).toFixed(2)}s${rank ? `  #${rank}` : ""}`, 1000, 154);
    context.textAlign = "left";
    requestAnimationFrame(draw);
  };
  recorder.start(250);
  await video.play();
  draw();
  await new Promise<void>((resolve) => { video.onended = () => resolve(); });
  recorder.stop();
  const result = await complete;
  canvasStream.getTracks().forEach((track) => track.stop());
  URL.revokeObjectURL(inputUrl);
  return result;
}

export async function shareOrDownload(blob: Blob) {
  const extension = blob.type.includes("mp4") ? "mp4" : "webm";
  const file = new File([blob], `yeet-flight.${extension}`, { type: blob.type });
  if (navigator.share && navigator.canShare?.({ files: [file] })) {
    await navigator.share({ files: [file], title: "My YEET", text: "How high can you go?" });
    return;
  }
  const anchor = document.createElement("a");
  anchor.href = URL.createObjectURL(blob);
  anchor.download = file.name;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(anchor.href), 5_000);
}
