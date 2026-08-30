function supportedMimeType() {
  const candidates = [
    "video/mp4;codecs=avc1.42E01E,mp4a.40.2",
    "video/mp4;codecs=h264,aac",
    "video/mp4",
    "video/webm;codecs=vp9,opus",
    "video/webm;codecs=vp8,opus",
    "video/webm"
  ];
  if (typeof window.MediaRecorder !== "function" || typeof MediaRecorder.isTypeSupported !== "function") {
    return undefined;
  }
  return candidates.find((candidate) => MediaRecorder.isTypeSupported(candidate));
}

type AudioContextConstructor = new () => AudioContext;
type SafariWindow = Window & typeof globalThis & { webkitAudioContext?: AudioContextConstructor };
type CaptureVideo = HTMLVideoElement & { captureStream?: () => MediaStream };

function audioContextConstructor() {
  return window.AudioContext ?? (window as SafariWindow).webkitAudioContext;
}

export function supportsPovRecording() {
  return Boolean(typeof navigator.mediaDevices?.getUserMedia === "function" &&
    typeof window.MediaRecorder === "function");
}

export function supportsBrandedPovExport() {
  const AudioContextClass = audioContextConstructor();
  const canCaptureVideoAudio = typeof (HTMLVideoElement.prototype as CaptureVideo).captureStream === "function";
  const canRouteVideoAudio = Boolean(AudioContextClass &&
    typeof AudioContextClass.prototype.createMediaElementSource === "function" &&
    typeof AudioContextClass.prototype.createMediaStreamDestination === "function");
  return Boolean(supportsPovRecording() &&
    typeof HTMLCanvasElement.prototype.captureStream === "function" &&
    (canCaptureVideoAudio || canRouteVideoAudio));
}

export class POVRecorder {
  private stream?: MediaStream;
  private recorder?: MediaRecorder;
  private chunks: Blob[] = [];

  async prepare() {
    if (!supportsPovRecording()) throw new Error("pov-unsupported");
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: "environment" }, width: { ideal: 1080 }, height: { ideal: 1920 } },
      audio: true
    });
  }

  start() {
    if (!this.stream) throw new Error("pov-not-prepared");
    this.chunks = [];
    const mimeType = supportedMimeType();
    this.recorder = new MediaRecorder(this.stream, mimeType ? { mimeType } : undefined);
    this.recorder.ondataavailable = (event) => { if (event.data.size) this.chunks.push(event.data); };
    this.recorder.start(250);
  }

  async stop() {
    const recorder = this.recorder;
    if (!recorder) throw new Error("pov-not-recording");
    return await new Promise<Blob>((resolve, reject) => {
      recorder.onerror = () => {
        this.stopTracks();
        reject(new Error("pov-recording-failed"));
      };
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

export async function createBrandedVideo(
  raw: Blob,
  airtimeMs: number,
  rank?: number,
  candidateRank?: number
) {
  if (!supportsBrandedPovExport()) throw new Error("pov-branded-export-unsupported");
  const inputUrl = URL.createObjectURL(raw);
  const video = document.createElement("video") as CaptureVideo;
  video.src = inputUrl;
  video.playsInline = true;
  video.muted = false;
  let audioContext: AudioContext | undefined;
  let audioSource: MediaElementAudioSourceNode | undefined;
  let canvasStream: MediaStream | undefined;
  let recorder: MediaRecorder | undefined;
  let animationFrame = 0;

  try {
    await new Promise<void>((resolve, reject) => {
      video.onloadedmetadata = () => resolve();
      video.onerror = () => reject(new Error("pov-replay-failed"));
    });

    const canvas = document.createElement("canvas");
    canvas.width = 1080;
    canvas.height = 1920;
    const context = canvas.getContext("2d")!;
    canvasStream = canvas.captureStream(30);

    let audioTracks = video.captureStream?.().getAudioTracks() ?? [];
    if (audioTracks.length === 0) {
      const AudioContextClass = audioContextConstructor();
      if (AudioContextClass) {
        audioContext = new AudioContextClass();
        if (audioContext.state === "suspended") await audioContext.resume();
        audioSource = audioContext.createMediaElementSource(video);
        const audioDestination = audioContext.createMediaStreamDestination();
        audioSource.connect(audioDestination);
        audioTracks = audioDestination.stream.getAudioTracks();
      }
    }
    if (audioTracks.length === 0) throw new Error("pov-audio-export-unsupported");
    audioTracks.forEach((track) => canvasStream?.addTrack(track));

    const mimeType = supportedMimeType();
    recorder = new MediaRecorder(canvasStream, {
      ...(mimeType ? { mimeType } : {}),
      videoBitsPerSecond: 8_000_000
    });
    const chunks: Blob[] = [];
    recorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
    const complete = new Promise<Blob>((resolve, reject) => {
      recorder!.onerror = () => reject(new Error("pov-export-failed"));
      recorder!.onstop = () => resolve(new Blob(chunks, { type: recorder!.mimeType || mimeType || raw.type }));
    });

    const draw = () => {
      if (video.ended || video.paused) return;
      const scale = Math.max(canvas.width / video.videoWidth, canvas.height / video.videoHeight);
      const width = video.videoWidth * scale;
      const height = video.videoHeight * scale;
      context.drawImage(video, (canvas.width - width) / 2, (canvas.height - height) / 2, width, height);

      const topShade = context.createLinearGradient(0, 0, 0, 650);
      topShade.addColorStop(0, "rgba(0,0,0,.74)");
      topShade.addColorStop(1, "rgba(0,0,0,0)");
      context.fillStyle = topShade;
      context.fillRect(0, 0, canvas.width, 650);

      const bottomShade = context.createLinearGradient(0, 1_000, 0, canvas.height);
      bottomShade.addColorStop(0, "rgba(0,0,0,0)");
      bottomShade.addColorStop(1, "rgba(0,0,0,.84)");
      context.fillStyle = bottomShade;
      context.fillRect(0, 1_000, canvas.width, 920);

      context.textAlign = "center";
      context.fillStyle = "white";
      context.font = "900 92px Impact, Anton, sans-serif";
      context.fillText("I YEETED", 540, 230);
      context.fillText("MY PHONE", 540, 330);

      context.fillStyle = "#FFD108";
      context.font = "900 220px Impact, Anton, sans-serif";
      context.fillText(`${(airtimeMs / 1000).toFixed(2)}s`, 540, 1_055);

      context.fillStyle = "white";
      context.font = "800 42px Inter, system-ui, sans-serif";
      if (rank) {
        context.fillText(`#${rank.toLocaleString()} IN THE WORLD`, 540, 1_145);
      } else if (candidateRank) {
        context.fillText(`WOULD RANK #${candidateRank.toLocaleString()}`, 540, 1_145);
      }

      context.font = "900 76px Impact, Anton, sans-serif";
      context.textAlign = "right";
      context.fillText("YEET", 990, 1_815);
      context.textAlign = "left";
      animationFrame = requestAnimationFrame(draw);
    };
    const ended = new Promise<void>((resolve) => { video.onended = () => resolve(); });
    recorder.start(250);
    await video.play();
    draw();
    await ended;
    recorder.stop();
    const output = await complete;
    cancelAnimationFrame(animationFrame);
    return output;
  } finally {
    cancelAnimationFrame(animationFrame);
    video.pause();
    if (recorder?.state !== "inactive") recorder?.stop();
    canvasStream?.getTracks().forEach((track) => track.stop());
    audioSource?.disconnect();
    if (audioContext && audioContext.state !== "closed") await audioContext.close();
    URL.revokeObjectURL(inputUrl);
  }
}

function videoFile(blob: Blob) {
  const extension = blob.type.includes("mp4") ? "mp4" : "webm";
  return new File([blob], `yeet-flight.${extension}`, { type: blob.type });
}

export function downloadVideo(blob: Blob) {
  const file = videoFile(blob);
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = file.name;
  anchor.hidden = true;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 5_000);
}

export async function shareVideo(blob: Blob): Promise<"shared" | "downloaded"> {
  const file = videoFile(blob);
  if (navigator.share && navigator.canShare?.({ files: [file] })) {
    await navigator.share({ files: [file], title: "My YEET", text: "How high can you go?" });
    return "shared";
  }
  downloadVideo(blob);
  return "downloaded";
}
