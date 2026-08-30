export const LEGAL_VERSION = "2026-08-30-analytics-v2";
export const LEGAL_EFFECTIVE_ISO_DATE = "2026-08-30";
export const LEGAL_EFFECTIVE_DATE = "August 30, 2026";
export const LEGAL_CONSENT_KEY = "yeet.legal.consent.v1";

export type LegalConsentStatus = "missing" | "outdated" | "current";

type LegalConsent = {
  version: string;
  acceptedAt: string;
};

export function legalConsentStatus(): LegalConsentStatus {
  try {
    const consent = JSON.parse(localStorage.getItem(LEGAL_CONSENT_KEY) ?? "null") as LegalConsent | null;
    if (!consent || typeof consent.acceptedAt !== "string" || !Number.isFinite(Date.parse(consent.acceptedAt))) {
      return "missing";
    }
    return consent.version === LEGAL_VERSION ? "current" : "outdated";
  } catch {
    return "missing";
  }
}

export function hasAcceptedCurrentLegalTerms() {
  return legalConsentStatus() === "current";
}

export function recordLegalConsent() {
  const consent: LegalConsent = {
    version: LEGAL_VERSION,
    acceptedAt: new Date().toISOString()
  };
  localStorage.setItem(LEGAL_CONSENT_KEY, JSON.stringify(consent));
}
