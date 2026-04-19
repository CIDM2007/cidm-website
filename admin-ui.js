(function () {
    function getTheme() {
        const defaults = {
            toast: {
                infoBg: '#1f2937',
                infoBorder: '#111827',
                successBg: '#166534',
                successBorder: '#14532d',
                errorBg: '#b91c1c',
                errorBorder: '#991b1b',
                text: '#ffffff',
                radius: '10px',
                shadow: '0 8px 24px rgba(0, 0, 0, 0.18)'
            },
            confirm: {
                backdrop: 'rgba(15, 23, 42, 0.55)',
                panelBg: '#0f172a',
                panelBorder: '#334155',
                panelRadius: '14px',
                panelShadow: '0 20px 48px rgba(0, 0, 0, 0.25)',
                title: '#f1f5f9',
                body: '#cbd5e1',
                cancelBg: '#1e293b',
                cancelBorder: '#334155',
                cancelText: '#cbd5e1',
                confirmBg: '#2563eb',
                confirmBorder: '#1d4ed8',
                confirmText: '#ffffff'
            },
            busyButton: {
                opacity: '0.7',
                cursor: 'not-allowed'
            },
            skeleton: {
                colorA: '#e5e7eb',
                colorB: '#f3f4f6',
                speed: '1.2s'
            }
        };

        const custom = window.CIDM_ADMIN_UI_THEME;
        if (!custom || typeof custom !== 'object') {
            return defaults;
        }

        return {
            toast: { ...defaults.toast, ...(custom.toast || {}) },
            confirm: { ...defaults.confirm, ...(custom.confirm || {}) },
            busyButton: { ...defaults.busyButton, ...(custom.busyButton || {}) },
            skeleton: { ...defaults.skeleton, ...(custom.skeleton || {}) }
        };
    }

    function getToastContainer() {
        let container = document.getElementById('cidm-toast-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'cidm-toast-container';
            container.style.position = 'fixed';
            container.style.top = '16px';
            container.style.right = '16px';
            container.style.zIndex = '9999';
            container.style.display = 'flex';
            container.style.flexDirection = 'column';
            container.style.gap = '8px';
            container.style.maxWidth = '360px';
            document.body.appendChild(container);
        }
        return container;
    }

    function resolveColors(type) {
        const theme = getTheme();
        if (type === 'success') {
            return { bg: theme.toast.successBg, border: theme.toast.successBorder };
        }
        if (type === 'error') {
            return { bg: theme.toast.errorBg, border: theme.toast.errorBorder };
        }
        return { bg: theme.toast.infoBg, border: theme.toast.infoBorder };
    }

    function showToast(message, type = 'info', duration = 2200) {
        const container = getToastContainer();
        const color = resolveColors(type);
        const theme = getTheme();

        const toast = document.createElement('div');
        toast.textContent = message;
        toast.style.background = color.bg;
        toast.style.border = '1px solid ' + color.border;
        toast.style.color = theme.toast.text;
        toast.style.borderRadius = theme.toast.radius;
        toast.style.padding = '10px 14px';
        toast.style.fontSize = '14px';
        toast.style.fontWeight = '700';
        toast.style.boxShadow = theme.toast.shadow;
        toast.style.opacity = '0';
        toast.style.transform = 'translateY(-8px)';
        toast.style.transition = 'opacity 0.2s ease, transform 0.2s ease';

        container.appendChild(toast);
        requestAnimationFrame(function () {
            toast.style.opacity = '1';
            toast.style.transform = 'translateY(0)';
        });

        window.setTimeout(function () {
            toast.style.opacity = '0';
            toast.style.transform = 'translateY(-8px)';
            window.setTimeout(function () {
                toast.remove();
            }, 220);
        }, duration);
    }

    function loadDomPurify() {
        if (window.DOMPurify) {
            return;
        }

        if (document.getElementById('cidm-dompurify-script')) {
            return;
        }

        const script = document.createElement('script');
        script.id = 'cidm-dompurify-script';
        script.src = 'https://cdn.jsdelivr.net/npm/dompurify@3.0.6/dist/purify.min.js';
        script.crossOrigin = 'anonymous';
        script.onload = () => {
            console.info('DOMPurify loaded.');
        };
        script.onerror = () => {
            console.warn('DOMPurify failed to load. Falling back to built-in sanitization.');
        };
        document.head.appendChild(script);
    }

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function sanitizeText(value) {
        const raw = String(value == null ? '' : value);
        if (window.DOMPurify && window.DOMPurify.sanitize) {
            return window.DOMPurify.sanitize(raw, {
                ALLOWED_TAGS: [],
                ALLOWED_ATTR: []
            });
        }
        return escapeHtml(raw);
    }

    function sanitizeUrl(value) {
        const urlString = String(value == null ? '' : value).trim();
        if (!urlString) return '#';

        try {
            const parsed = new URL(urlString, window.location.href);
            const allowed = ['http:', 'https:', 'mailto:'];
            if (!allowed.includes(parsed.protocol)) {
                return '#';
            }
            return window.DOMPurify && window.DOMPurify.sanitize
                ? window.DOMPurify.sanitize(parsed.toString(), { ALLOWED_TAGS: [], ALLOWED_ATTR: [] })
                : parsed.toString();
        } catch (_e) {
            return '#';
        }
    }

    function sanitizeHtml(value) {
        const raw = String(value == null ? '' : value);
        if (window.DOMPurify && window.DOMPurify.sanitize) {
            return window.DOMPurify.sanitize(raw, {
                ALLOWED_TAGS: ['br'],
                ALLOWED_ATTR: []
            });
        }
        return escapeHtml(raw);
    }

    loadDomPurify();

    function createConfirmElements(message, confirmText, cancelText) {
        const theme = getTheme();
        const backdrop = document.createElement('div');
        backdrop.style.position = 'fixed';
        backdrop.style.inset = '0';
        backdrop.style.background = theme.confirm.backdrop;
        backdrop.style.display = 'flex';
        backdrop.style.alignItems = 'center';
        backdrop.style.justifyContent = 'center';
        backdrop.style.padding = '20px';
        backdrop.style.zIndex = '10000';

        const dialog = document.createElement('div');
        dialog.style.width = '100%';
        dialog.style.maxWidth = '420px';
        dialog.style.background = theme.confirm.panelBg;
        dialog.style.borderRadius = theme.confirm.panelRadius;
        dialog.style.boxShadow = theme.confirm.panelShadow;
        dialog.style.padding = '18px 18px 16px';
        dialog.style.border = '1px solid ' + theme.confirm.panelBorder;

        const title = document.createElement('div');
        title.textContent = '確認';
        title.style.fontSize = '16px';
        title.style.fontWeight = '700';
        title.style.color = theme.confirm.title;
        title.style.marginBottom = '10px';

        const text = document.createElement('div');
        text.textContent = message;
        text.style.fontSize = '14px';
        text.style.lineHeight = '1.6';
        text.style.color = theme.confirm.body;
        text.style.marginBottom = '16px';

        const actions = document.createElement('div');
        actions.style.display = 'flex';
        actions.style.justifyContent = 'flex-end';
        actions.style.gap = '10px';

        const cancelButton = document.createElement('button');
        cancelButton.type = 'button';
        cancelButton.textContent = cancelText;
        cancelButton.style.border = '1px solid ' + theme.confirm.cancelBorder;
        cancelButton.style.background = theme.confirm.cancelBg;
        cancelButton.style.color = theme.confirm.cancelText;
        cancelButton.style.borderRadius = '8px';
        cancelButton.style.padding = '8px 14px';
        cancelButton.style.fontWeight = '700';
        cancelButton.style.cursor = 'pointer';

        const confirmButton = document.createElement('button');
        confirmButton.type = 'button';
        confirmButton.textContent = confirmText;
        confirmButton.style.border = '1px solid ' + theme.confirm.confirmBorder;
        confirmButton.style.background = theme.confirm.confirmBg;
        confirmButton.style.color = theme.confirm.confirmText;
        confirmButton.style.borderRadius = '8px';
        confirmButton.style.padding = '8px 14px';
        confirmButton.style.fontWeight = '700';
        confirmButton.style.cursor = 'pointer';

        actions.appendChild(cancelButton);
        actions.appendChild(confirmButton);
        dialog.appendChild(title);
        dialog.appendChild(text);
        dialog.appendChild(actions);
        backdrop.appendChild(dialog);

        return { backdrop, cancelButton, confirmButton };
    }

    function showConfirm(message, options) {
        const config = options || {};
        const confirmText = config.confirmText || '削除する';
        const cancelText = config.cancelText || 'キャンセル';

        return new Promise(function (resolve) {
            const elems = createConfirmElements(message, confirmText, cancelText);

            function cleanup(result) {
                document.removeEventListener('keydown', onKeyDown);
                elems.backdrop.remove();
                resolve(result);
            }

            function onKeyDown(event) {
                if (event.key === 'Escape') {
                    cleanup(false);
                }
            }

            elems.cancelButton.addEventListener('click', function () {
                cleanup(false);
            });

            elems.confirmButton.addEventListener('click', function () {
                cleanup(true);
            });

            elems.backdrop.addEventListener('click', function (event) {
                if (event.target === elems.backdrop) {
                    cleanup(false);
                }
            });

            document.addEventListener('keydown', onKeyDown);
            document.body.appendChild(elems.backdrop);
            elems.confirmButton.focus();
        });
    }

    async function runWithButtonBusy(button, task, busyText) {
        if (!button || typeof task !== 'function') {
            return task ? task() : undefined;
        }

        const theme = getTheme();

        const originalText = button.textContent;
        const originalDisabled = button.disabled;
        button.disabled = true;
        button.textContent = busyText || '処理中...';
        button.style.opacity = theme.busyButton.opacity;
        button.style.cursor = theme.busyButton.cursor;

        try {
            return await task();
        } finally {
            button.disabled = originalDisabled;
            button.textContent = originalText;
            button.style.opacity = '';
            button.style.cursor = '';
        }
    }

    function ensureSkeletonStyles() {
        if (document.getElementById('cidm-skeleton-style')) {
            return;
        }

        const theme = getTheme();

        const style = document.createElement('style');
        style.id = 'cidm-skeleton-style';
        style.textContent = [
            '.cidm-skeleton-line {',
            '  border-radius: 9999px;',
            '  background: linear-gradient(90deg, ' + theme.skeleton.colorA + ' 25%, ' + theme.skeleton.colorB + ' 40%, ' + theme.skeleton.colorA + ' 65%);',
            '  background-size: 300% 100%;',
            '  animation: cidm-skeleton-shimmer ' + theme.skeleton.speed + ' infinite;',
            '}',
            '@keyframes cidm-skeleton-shimmer {',
            '  0% { background-position: 100% 0; }',
            '  100% { background-position: 0 0; }',
            '}'
        ].join('\n');

        document.head.appendChild(style);
    }

    function getSkeletonLine(width = '100%', height = '0.95rem') {
        ensureSkeletonStyles();
        return '<div class="cidm-skeleton-line" style="width:' + width + ';height:' + height + ';"></div>';
    }

    window.cidmAdminUi = {
        showToast: showToast,
        showConfirm: showConfirm,
        runWithButtonBusy: runWithButtonBusy,
        getSkeletonLine: getSkeletonLine,
        sanitizeText: sanitizeText,
        sanitizeUrl: sanitizeUrl,
        sanitizeHtml: sanitizeHtml
    };
})();
