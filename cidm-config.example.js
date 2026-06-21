// Copy this file to cidm-config.js and fill in the actual values.
// cidm-config.js is git-ignored; never commit the real key.
// The anon/publishable key is public by design (browser-visible),
// but keeping it out of git avoids exposing it in public repositories.

window.CIDM_SUPABASE_URL = 'https://YOUR_PROJECT_ID.supabase.co';
window.CIDM_SUPABASE_PUBLISHABLE_KEY = 'REPLACE_WITH_YOUR_SB_PUBLISHABLE_KEY';
window.CIDM_SUPABASE_ANON_KEY = window.CIDM_SUPABASE_PUBLISHABLE_KEY;

// Optional admin auth policy for additional admin whitelist checks.
// window.CIDM_ADMIN_AUTH_POLICY = {
//   allowedEmails: ['admin@example.com'],
//   requireAdminFlag: true,
//};
