(function () {
    function buildLoginUrl(loginUrl) {
        const trimmed = String(loginUrl || '').trim();
        if (trimmed) {
            return trimmed;
        }

        return new URL('index.html', window.location.href).href;
    }

    async function sendMemberLoginMail(payload) {
        const email = String(payload?.email || payload?.login_id || '').trim();
        const loginId = String(payload?.login_id || email || '').trim();
        const password = String(payload?.password || payload?.initial_password || '').trim();
        const memberName = String(payload?.member_name || payload?.staff_name || '').trim();
        const companyName = String(payload?.company_name || payload?.org_name || '').trim();
        const loginUrl = buildLoginUrl(payload?.login_url);

        if (!email || !loginId || !password) {
            throw new Error('メール送信に必要な情報が不足しています。');
        }

        const response = await fetch('https://uhhhifbotqidqeceqyis.functions.supabase.co/send-member-login-mail', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                email,
                login_id: loginId,
                password,
                member_name: memberName,
                company_name: companyName,
                login_url: loginUrl
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(errorText || 'ログイン案内メールの送信に失敗しました。');
        }

        return response.json();
    }

    window.cidmAdminMail = {
        sendMemberLoginMail
    };
})();
