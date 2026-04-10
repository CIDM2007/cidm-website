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

    async function ensureAuthenticated(supabaseClient, redirectUrl = 'index.html', policy) {
        try {
            if (!supabaseClient) {
                window.location.href = redirectUrl;
                return false;
            }
            const { data } = await supabaseClient.auth.getUser();
            if (!data || !data.user) {
                window.location.href = redirectUrl;
                return false;
            }
            const resolvedPolicy = policy || getDefaultPolicy();
            if (!isAdminAuthorized(data.user, resolvedPolicy)) {
                window.location.href = redirectUrl;
                return false;
            }
            return true;
        } catch (e) {
            window.location.href = redirectUrl;
            return false;
        }
    }

    async function signOutAndRedirect(supabaseClient, redirectUrl = 'index.html') {
        try {
            if (supabaseClient) {
                await supabaseClient.auth.signOut();
            }
        } catch (e) {
            // Continue redirect even if sign-out fails.
        }
        window.location.href = redirectUrl;
    }

    window.cidmAdminAuth = {
        createSupabaseClient,
        ensureAuthenticated,
        signOutAndRedirect,
        isAdminAuthorized
    };
})();
