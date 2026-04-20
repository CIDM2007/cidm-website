(function () {
    // Note: Supabase keys are now handled via Edge Functions for security.
    // Admin pages should use Edge Functions for data operations.

    const ADMIN_SESSION_STORAGE_KEY = 'admin-session';

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

    async function restoreAdminSession(supabaseClient) {
        if (!supabaseClient || !supabaseClient.auth || typeof supabaseClient.auth.setSession !== 'function') {
            return false;
        }

        try {
            const raw = sessionStorage.getItem(ADMIN_SESSION_STORAGE_KEY);
            if (!raw) {
                return false;
            }

            const parsed = JSON.parse(raw);
            const session = parsed && parsed.session ? parsed.session : parsed;
            const accessToken = session && session.access_token;
            const refreshToken = session && session.refresh_token;

            if (!accessToken || !refreshToken) {
                return false;
            }

            const { error } = await supabaseClient.auth.setSession({
                access_token: accessToken,
                refresh_token: refreshToken
            });

            if (error) {
                console.warn('Failed to restore admin session:', error.message);
                return false;
            }

            return true;
        } catch (e) {
            console.warn('Failed to parse saved admin session:', e);
            return false;
        }
    }

    async function getAuthenticatedAdminUser(supabaseClient, policy = {}) {
        if (!supabaseClient) {
            return null;
        }

        try {
            let { data: { user }, error } = await supabaseClient.auth.getUser();

            if (!user) {
                const restored = await restoreAdminSession(supabaseClient);
                if (restored) {
                    const retry = await supabaseClient.auth.getUser();
                    user = retry.data && retry.data.user;
                    error = retry.error;
                }
            }

            if (error || !user) {
                return null;
            }

            const effectivePolicy = policy && typeof policy === 'object' ? { ...getDefaultPolicy(), ...policy } : getDefaultPolicy();
            if (!isAdminAuthorized(user, effectivePolicy)) {
                return null;
            }

            return user;
        } catch (e) {
            console.error('Authentication check failed:', e);
            return null;
        }
    }

    async function ensureAuthenticated(supabaseClient, redirectUrl = 'index.html', policy = {}) {
        if (!supabaseClient) {
            console.warn('Supabase client is not available. Redirecting to login.');
            window.location.href = redirectUrl;
            return false;
        }

        const user = await getAuthenticatedAdminUser(supabaseClient, policy);
        if (!user) {
            console.warn('User is not authenticated or authorized as admin.');
            window.location.href = redirectUrl;
            return false;
        }

        return true;
    }

    function clearSupabaseStorageTokens() {
        const supabaseUrl = String(window.CIDM_SUPABASE_URL || '');
        const match = supabaseUrl.match(/^https:\/\/([^.]+)\.supabase\.co/i);
        if (!match) {
            return;
        }

        const projectRef = match[1];
        const tokenKeys = [
            `sb-${projectRef}-auth-token`,
            `sb-${projectRef}-auth-token-code-verifier`
        ];

        tokenKeys.forEach((key) => {
            try {
                localStorage.removeItem(key);
                sessionStorage.removeItem(key);
            } catch (_e) {
                // Ignore storage cleanup errors and continue logout flow.
            }
        });
    }

    async function signOutAndRedirect(supabaseClient, redirectUrl = 'index.html') {
        try {
            if (supabaseClient && supabaseClient.auth && typeof supabaseClient.auth.signOut === 'function') {
                await supabaseClient.auth.signOut({ scope: 'local' });
            }
        } catch (e) {
            console.warn('Supabase signOut failed. Continuing local cleanup.', e);
        } finally {
            sessionStorage.removeItem(ADMIN_SESSION_STORAGE_KEY);
            clearSupabaseStorageTokens();
            window.location.href = redirectUrl;
        }
    }
    // AUTH_BYPASS_END

    window.cidmAdminAuth = {
        createSupabaseClient,
        getAuthenticatedAdminUser,
        ensureAuthenticated,
        signOutAndRedirect,
        isAdminAuthorized
    };
})();
