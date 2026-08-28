import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatSeconds(milliseconds?: number | null) {
  return milliseconds == null ? "—" : `${(milliseconds / 1000).toFixed(2)}s`;
}

export function normalizeHandle(value: string) {
  return value.trim().toLowerCase().replace(/^@/, "");
}

export function isValidHandle(value: string) {
  return /^[a-z0-9_]{3,20}$/.test(normalizeHandle(value));
}
