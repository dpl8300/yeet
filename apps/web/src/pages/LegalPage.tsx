import { Link } from "react-router-dom";
import { LEGAL_EFFECTIVE_DATE, LEGAL_VERSION } from "../lib/legal";

export function LegalPage({ type }: { type: "privacy" | "terms" }) {
  return (
    <main className="legal-shell">
      <article className="legal-card">
        <Link to="/" className="back-link">← BACK TO YEET</Link>
        <p className="eyebrow">YEET · EFFECTIVE <time dateTime={LEGAL_VERSION}>{LEGAL_EFFECTIVE_DATE.toUpperCase()}</time></p>
        <h1>{type === "privacy" ? "PRIVACY NOTICE" : "TERMS OF USE"}</h1>
        {type === "privacy" ? <Privacy /> : <Terms />}
      </article>
    </main>
  );
}

function Privacy() {
  return <>
    <p>This Privacy Notice explains how YEET collects, uses, discloses, and retains information through yeetphone.com and the installed web app. YEET is the service operator. Questions and privacy requests can be sent to <a href="mailto:support@yeetphone.com">support@yeetphone.com</a>.</p>

    <h2>THE SHORT VERSION</h2><p>Guest play does not require an account. POV video stays on your device unless you choose to save or share it. Signed-in ranked submissions send a raw motion trace to YEET for validation, but YEET stores only the resulting attempt measurements. YEET uses Vercel Web Analytics for aggregated traffic statistics, but does not sell personal information, run advertising, or use cross-site behavioral tracking.</p>

    <h2>INFORMATION YOU PROVIDE</h2><p>If you sign in, YEET and its authentication provider process your email address or the identity information Google makes available, such as your account identifier and email address. You may provide a public handle. If you contact support, YEET processes your address, message, attachments, and any other information you include.</p>

    <h2>GAMEPLAY AND LEADERBOARD DATA</h2><p>For guest rank estimates, YEET sends the measured airtime to Supabase without storing an account-linked attempt. For signed-in ranked submissions, YEET temporarily sends the attempt identifier and raw motion samples to a Supabase Edge Function. The function validates the trace and discards it after deriving the airtime, stationary-check peak, impact peak, airborne sample count, and related timestamps. Those derived metrics, your handle, personal best, and rank are stored until you delete your account or YEET removes them under the Terms.</p>

    <h2>PUBLIC INFORMATION</h2><p>Your handle, personal-best airtime, rank, and achievement time may appear on the public leaderboard. Do not use your legal name or other sensitive information as a handle. Changing your handle updates the name associated with your leaderboard entry.</p>

    <h2>DEVICE DATA AND PERMISSIONS</h2><p>Motion access is requested when you start an attempt. Camera and microphone access are requested only when Record POV is enabled. POV recordings and branded previews are created in temporary browser memory and are not uploaded by YEET. If you choose Save or Share, your browser or operating system sends the file to the destination or third-party service you select. You can revoke device permissions in browser settings.</p>

    <h2>LOCAL STORAGE</h2><p>YEET stores the current legal-consent version and time, tutorial status, POV preference, authentication session, and the last leaderboard snapshot in browser storage. The PWA also caches application files for offline loading. These remain until they expire, are replaced, you sign out where applicable, or you clear the site’s browser data.</p>

    <h2>AUTOMATIC, ANALYTICS, AND SERVICE DATA</h2><p>YEET and its service providers may process IP address, browser and device details, timestamps, request metadata, security events, and diagnostic or delivery logs when your device connects to the service. Vercel Web Analytics records anonymous page views and aggregated information such as the page path, referrer, filtered query parameters, general location, operating system, browser, and device type. Vercel identifies a daily visitor using a request-derived hash rather than cookies and discards that visitor identifier after 24 hours. Loading Google Fonts also sends ordinary request data to Google.</p>

    <h2>HOW INFORMATION IS USED</h2><p>YEET uses information to run and secure gameplay, authenticate accounts, validate and rank attempts, display the leaderboard, understand aggregate site traffic, remember preferences and consent, deliver sign-in messages, provide support, prevent abuse, diagnose failures, enforce the Terms, and comply with law.</p>

    <h2>SERVICE PROVIDERS AND DISCLOSURE</h2><p>Information is processed as needed by Vercel for web hosting and privacy-focused Web Analytics, Supabase for authentication and leaderboard services, Resend for authentication and outbound support email, Namecheap for support-email forwarding, the destination support-mail provider, and Google for OAuth and hosted fonts. YEET may also disclose information when reasonably necessary to comply with law, protect users or the public, investigate abuse, or complete a business transfer subject to this Notice.</p>

    <h2>NO SALE, ADS, OR CROSS-SITE TRACKING</h2><p>YEET does not use advertising analytics, sell personal information, or share it for cross-context behavioral advertising. Vercel Web Analytics is cookie-free and reports aggregated traffic without identifying you across different days or websites. Because YEET does not sell, share for behavioral advertising, or track your activity across unrelated websites, browser Do Not Track and Global Privacy Control signals do not change the service’s current behavior.</p>

    <h2>RETENTION</h2><p>Account and derived attempt data are retained while your account exists. Raw ranked-submission traces are used transiently and are not stored as database records. Temporary POV data lasts only for the current attempt unless you save or share it. Vercel retains aggregated analytics according to the project’s plan and settings, while its daily visitor identifier expires after 24 hours. Support communications, authentication records, and operational logs are retained only as reasonably needed for support, security, legal obligations, and provider operations.</p>

    <h2>YOUR CHOICES AND REQUESTS</h2><p>You may play as a guest, leave POV recording off, revoke permissions, clear local site data, change your handle, sign out, or delete your account in Settings. Account deletion removes the Auth user and cascades to the profile, attempts, and personal best. To request access, correction, or deletion of other information, email <a href="mailto:support@yeetphone.com">support@yeetphone.com</a>. YEET may need to verify your identity before acting.</p>

    <h2>SECURITY AND U.S. PROCESSING</h2><p>YEET uses reasonable technical and organizational safeguards, but no browser, transmission, or storage system is completely secure. YEET and its providers process information in the United States and other locations where they operate.</p>

    <h2>ADULTS ONLY</h2><p>YEET is intended only for people age 18 or older and does not knowingly collect personal information from minors. If you believe a minor has provided information, contact <a href="mailto:support@yeetphone.com">support@yeetphone.com</a> so it can be investigated and deleted as appropriate.</p>

    <h2>CHANGES</h2><p>YEET may update this Notice as the service or law changes. The current effective date appears above. Material changes will be presented prominently in the app or through another reasonable notice.</p>
  </>;
}

function Terms() {
  return <>
    <p>These Terms of Use are a binding agreement between you and YEET governing yeetphone.com and the installed web app. By checking the acknowledgment and selecting “I Agree — Let’s Yeet,” or by using YEET afterward, you accept these Terms. If you do not agree, do not use YEET.</p>

    <h2>18+ ONLY</h2><p>You must be at least 18 years old and legally capable of entering this agreement. YEET is not intended for minors. You may not allow a minor to use YEET through your device or account.</p>

    <h2>IMPORTANT SAFETY WARNING</h2><p>YEET involves intentionally tossing and catching a phone. A case reduces some risk but does not make the activity safe. A missed or uncontrolled throw can cause device damage, battery damage, data loss, property damage, serious bodily injury, or death. Use only a controlled vertical toss within easy reach in a large, clear area. Stay away from people, animals, traffic, vehicles, water, stairs, ledges, windows, breakable objects, ceiling fans, power lines, and other overhead hazards. Never play while driving, riding, walking, impaired, distracted, or using a damaged device or battery. Stop immediately if conditions become unsafe.</p>

    <h2>ASSUMPTION OF RISK</h2><p>You alone decide whether, where, and how to play. You understand and voluntarily accept all inherent and reasonably foreseeable risks associated with throwing, dropping, catching, recording with, or sharing content from your device. You are responsible for your device, data, surroundings, conduct, and any injury or damage you cause. Never increase toss height, force, or difficulty to improve a score or leaderboard position.</p>

    <h2>RELEASE OF ORDINARY-NEGLIGENCE CLAIMS</h2><p>To the fullest extent permitted by Washington law, you release YEET and its owner, operator, agents, and service providers from claims, liabilities, losses, and expenses arising from ordinary negligence connected with your decision to use YEET or participate in the activity. This release does not apply to gross negligence, reckless or willful misconduct, fraud, or any liability that applicable law does not allow to be waived.</p>

    <h2>MEASUREMENTS AND CASUAL RANKINGS</h2><p>Sensor readings, airtime, catches, personal bests, and ranks are approximate entertainment results. They are not safety information, hardware-attested measurements, or professional advice. Device hardware, browsers, sampling rates, networks, and detection errors can affect results. No prizes are awarded. Do not rely on YEET to determine whether a toss is safe or to protect a person, device, or property.</p>

    <h2>ACCOUNTS AND PUBLIC DATA</h2><p>An account is optional, but saving a ranked score requires sign-in and a handle. Your handle, personal best, rank, and achievement time may be public. You grant YEET a worldwide, nonexclusive, royalty-free license to host, reproduce, and display that information solely to operate and promote the leaderboard and service. The license ends when the information is deleted, subject to reasonable backup and legal retention. YEET may reject unreliable traces and remove scores, handles, or accounts that are abusive, misleading, unlawful, unsafe, or disruptive.</p>

    <h2>PRIVACY, ANALYTICS, AND PROVIDERS</h2><p>YEET processes information as described in the Privacy Notice, including through service providers that host, secure, authenticate, support, and measure use of the service. YEET uses Vercel Web Analytics to understand aggregated site traffic without third-party analytics cookies or cross-site behavioral tracking. Third-party services you choose to use, including OAuth, email, and sharing destinations, may apply their own terms and privacy practices.</p>

    <h2>POV RECORDING AND SHARING</h2><p>POV recordings remain yours and are processed locally unless you choose to save or share them. You are responsible for obtaining consent from anyone recorded, complying with recording and privacy laws, reviewing the video before sharing, and choosing lawful recipients and platforms. Once you share a file through another service, that service’s terms and privacy practices apply and YEET cannot control further use.</p>

    <h2>ACCEPTABLE USE</h2><p>Do not use YEET to harm or threaten anyone, damage property, record unlawfully, impersonate another person, manipulate scores, probe or disrupt the service, bypass security, introduce malicious code, or violate law. YEET may suspend or terminate access and preserve or disclose relevant information when reasonably necessary to protect the service, users, or public.</p>

    <h2>YEET PROPERTY</h2><p>YEET, its interface, branding, graphics, software, and other service materials are owned by YEET or its licensors and are protected by applicable intellectual-property laws. These Terms give you a limited, revocable, nontransferable right to use the service for personal, noncommercial entertainment.</p>

    <h2>AS-IS SERVICE AND WARRANTY DISCLAIMER</h2><p>To the fullest extent permitted by law, YEET is provided “as is” and “as available,” without express or implied warranties, including merchantability, fitness for a particular purpose, noninfringement, accuracy, availability, compatibility, or safety. YEET does not promise uninterrupted operation, accurate measurements, successful recording or sharing, account availability, data preservation, or compatibility with every device.</p>

    <h2>LIMITATION OF LIABILITY</h2><p>To the fullest extent permitted by law, YEET and its owner, operator, agents, and service providers will not be liable for indirect, incidental, special, consequential, exemplary, or punitive damages, or for lost data, lost profits, device damage, property damage, or personal injury arising from your use of YEET. Their combined liability for all claims will not exceed the greater of the amount you paid YEET during the 12 months before the claim or US $100. These limits do not exclude liability that applicable law does not permit YEET to limit.</p>

    <h2>INDEMNITY</h2><p>To the extent permitted by law, you will defend, indemnify, and hold harmless YEET and its owner and operator from third-party claims, damages, and reasonable expenses arising from your unsafe or unlawful conduct, violation of these Terms, infringement of another person’s rights, or recording or sharing activity. This obligation does not cover a claim to the extent caused by conduct for which YEET cannot lawfully shift responsibility.</p>

    <h2>CHANGES AND TERMINATION</h2><p>YEET may change, suspend, or discontinue features and may update these Terms. Material Terms changes will require a new in-app acknowledgment before further gameplay. You may stop using YEET at any time and delete a signed-in account through Settings.</p>

    <h2>WASHINGTON LAW</h2><p>Washington law governs these Terms without regard to conflict-of-law rules. You and YEET consent to the exclusive jurisdiction of state and federal courts with jurisdiction in Washington State, except where applicable consumer law requires otherwise.</p>

    <h2>GENERAL</h2><p>If any provision is unenforceable, it will be limited to the minimum extent necessary and the remaining provisions will continue. Failure to enforce a provision is not a waiver. These Terms and the Privacy Notice are the entire agreement about the service and replace prior versions.</p>

    <h2>CONTACT</h2><p>Questions or legal notices may be sent to <a href="mailto:support@yeetphone.com">support@yeetphone.com</a>.</p>
  </>;
}
