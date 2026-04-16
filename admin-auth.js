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
        // Supabase client creation is disabled for security.
        // Use Edge Functions instead.
        console.warn('Supabase client creation is disabled. Use Edge Functions for data operations.');
        return null;
    }

    async function ensureAuthenticated(supabaseClient, redirectUrl = 'index.html', policy = {}) {
        // AUTH_BYPASS_START — 認証を一時停止中。本番環境では復元が必須。
        // ローカル開発・テスト用に認証をスキップします
        return true;
        // AUTH_BYPASS_END
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
