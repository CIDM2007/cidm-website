(function () {
    const DEFAULT_SUPABASE_URL = 'https://uhhhifbotqidqeceqyis.supabase.co';
    const DEFAULT_SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoaGhpZmJvdHFpZHFlY2VxeWlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1ODc4NTQsImV4cCI6MjA5MTE2Mzg1NH0.D_mXbECP3g4ODa2r-OQG92eHiKYWqCjdFAxga91ZC8Q';

    function getDefaultPolicy() {
        const policy = window.CIDM_ADMIN_AUTH_POLICY;
        if (!policy || typeof policy !== 'object') {
            return {};
        }
        return policy;
    }

    function isAdminAuthorized(user, policy = {}) {
        if (!user) {
            return false;
        }

        const allowedEmails = Array.isArray(policy.allowedEmails) ? policy.allowedEmails : [];
        if (allowedEmails.length > 0) {
            const userEmail = (user.email || '').toLowerCase();
            const normalizedAllowed = allowedEmails
                .map((email) => String(email).toLowerCase().trim())
                .filter(Boolean);
            if (!normalizedAllowed.includes(userEmail)) {
                return false;
            }
        }

        if (policy.requireAdminFlag === true) {
            const userFlag = user.user_metadata && user.user_metadata.is_admin === true;
            const appFlag = user.app_metadata && user.app_metadata.is_admin === true;
            if (!userFlag && !appFlag) {
                return false;
            }
        }

        return true;
    }

    function createSupabaseClient(url = DEFAULT_SUPABASE_URL, key = DEFAULT_SUPABASE_KEY) {
        const supabaseLib = window.supabase;
        if (!supabaseLib || typeof supabaseLib.createClient !== 'function') {
            return null;
        }
        return window.supabaseClient || supabaseLib.createClient(url, key);
    }

    // AUTH_BYPASS_START — 認証を一時停止中。復元時はこのブロックを元の実装に戻すこと。
    async function ensureAuthenticated(_supabaseClient, _redirectUrl, _policy) {
        return true;
    }

    async function signOutAndRedirect(_supabaseClient, redirectUrl = 'index.html') {
        window.location.href = redirectUrl;
    }
    // AUTH_BYPASS_END

    window.cidmAdminAuth = {
        createSupabaseClient,
        ensureAuthenticated,
        signOutAndRedirect,
        isAdminAuthorized
    };
})();
