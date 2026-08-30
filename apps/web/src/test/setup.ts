import "@testing-library/jest-dom/vitest";
import { afterEach } from "vitest";
import { cleanup } from "@testing-library/react";

const memory = new Map<string, string>();
const storage: Storage = {
  get length() { return memory.size; },
  clear: () => memory.clear(),
  getItem: (key) => memory.get(key) ?? null,
  key: (index) => Array.from(memory.keys())[index] ?? null,
  removeItem: (key) => { memory.delete(key); },
  setItem: (key, value) => { memory.set(key, String(value)); }
};
Object.defineProperty(globalThis, "localStorage", { configurable: true, value: storage });
Object.defineProperty(window, "localStorage", { configurable: true, value: storage });
Object.defineProperty(URL, "createObjectURL", { configurable: true, value: () => "blob:yeet-test" });
Object.defineProperty(URL, "revokeObjectURL", { configurable: true, value: () => undefined });
Object.defineProperty(HTMLMediaElement.prototype, "play", { configurable: true, value: async () => undefined });
Object.defineProperty(HTMLMediaElement.prototype, "pause", { configurable: true, value: () => undefined });

afterEach(() => {
  cleanup();
  localStorage.clear();
});
