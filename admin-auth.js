(function () {
    // Note: Supabase keys are now handled via Edge Functions for security.
    // Admin pages should use Edge Functions for data operations.

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

    function createSupabaseClient() {
        // Initialize Supabase client from global config
        // Both CIDM_SUPABASE_URL and CIDM_SUPABASE_ANON_KEY must be set in the calling HTML page
        const SUPABASE_URL = window.CIDM_SUPABASE_URL;
        const SUPABASE_ANON_KEY = window.CIDM_SUPABASE_ANON_KEY;
        
        if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
            console.error('Supabase configuration is missing. Each admin page must set window.CIDM_SUPABASE_URL and window.CIDM_SUPABASE_ANON_KEY before admin-auth.js is loaded.');
            return null;
        }
        
        try {
            if (!window.supabase || !window.supabase.createClient) {
                console.error('Supabase library (@supabase/supabase-js) is not loaded.');
                return null;
            }
            return window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
        } catch (e) {
            console.error('Failed to create Supabase client:', e);
            return null;
        }
    }

    async function ensureAuthenticated(supabaseClient, redirectUrl = 'index.html', policy = {}) {
        if (!supabaseClient) {
            console.warn('Supabase client is not available. Redirecting to login.');
            window.location.href = redirectUrl;
            return false;
        }

        try {
            const { data: { user }, error } = await supabaseClient.auth.getUser();
            
            if (error || !user) {
                console.warn('User not authenticated:', error?.message || 'No user found');
                window.location.href = redirectUrl;
                return false;
            }

            // Check authorization policy
            const policy_obj = getDefaultPolicy();
            if (!isAdminAuthorized(user, policy_obj)) {
                console.warn('User is not authorized as admin:', user.email);
                window.location.href = redirectUrl;
                return false;
            }

            return true;
        } catch (e) {
            console.error('Authentication check failed:', e);
            window.location.href = redirectUrl;
            return false;
        }
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
