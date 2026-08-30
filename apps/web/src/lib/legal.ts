export const LEGAL_VERSION = "2026-08-30";
export const LEGAL_EFFECTIVE_DATE = "August 30, 2026";
export const LEGAL_CONSENT_KEY = "yeet.legal.consent.v1";

type LegalConsent = {
  version: string;
  acceptedAt: string;
};

export function hasAcceptedCurrentLegalTerms() {
  try {
    const consent = JSON.parse(localStorage.getItem(LEGAL_CONSENT_KEY) ?? "null") as LegalConsent | null;
    return consent?.version === LEGAL_VERSION
      && typeof consent.acceptedAt === "string"
      && Number.isFinite(Date.parse(consent.acceptedAt));
  } catch {
    return false;
  }
}

export function recordLegalConsent() {
  const consent: LegalConsent = {
    version: LEGAL_VERSION,
    acceptedAt: new Date().toISOString()
  };
  localStorage.setItem(LEGAL_CONSENT_KEY, JSON.stringify(consent));
}
