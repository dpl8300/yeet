import { useEffect } from "react";
import { Analytics, type BeforeSendEvent } from "@vercel/analytics/react";
import { Navigate, Route, Routes } from "react-router-dom";
import { redactAnalyticsUrl, trackEvent } from "./lib/analytics";
import { AuthCallback } from "./pages/AuthCallback";
import { LegalPage } from "./pages/LegalPage";
import { YeetExperience } from "./pages/YeetExperience";

export function App() {
  return (
    <>
      <AppAnalytics />
      <Routes>
        <Route path="/" element={<YeetExperience />} />
        <Route path="/auth/callback" element={<AuthCallback />} />
        <Route path="/privacy" element={<LegalPage type="privacy" />} />
        <Route path="/terms" element={<LegalPage type="terms" />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  );
}

function AppAnalytics() {
  useEffect(() => {
    const installed = () => trackEvent("pwa_installed");
    window.addEventListener("appinstalled", installed);
    return () => window.removeEventListener("appinstalled", installed);
  }, []);
  return <Analytics beforeSend={(event: BeforeSendEvent) => redactAnalyticsUrl(event)} />;
}
