import { Analytics } from "@vercel/analytics/react";
import { Navigate, Route, Routes } from "react-router-dom";
import { AuthCallback } from "./pages/AuthCallback";
import { LegalPage } from "./pages/LegalPage";
import { YeetExperience } from "./pages/YeetExperience";

export function App() {
  return (
    <>
      <Routes>
        <Route path="/" element={<YeetExperience />} />
        <Route path="/auth/callback" element={<AuthCallback />} />
        <Route path="/privacy" element={<LegalPage type="privacy" />} />
        <Route path="/terms" element={<LegalPage type="terms" />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <Analytics />
    </>
  );
}
