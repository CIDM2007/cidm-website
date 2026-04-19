# CIDM セキュリティー監査レポート

**作成日:** 2026年4月19日  
**監査対象:** CIDM ウェブシステム全体（HTML/CSS/JS、Supabase Edge Functions、SQL マイグレーション）  
**重大度レベル:** 🔴 **CRITICAL** ～ 🟡 **MEDIUM**

---

## 📋 エグゼクティブサマリー

### 検出された脆弱性の概要

| 重大度 | 件数 | カテゴリー |
|:---:|:---:|---|
| 🔴 **CRITICAL** | 3 | 認証バイパス、CORS設定、セッション管理 |
| 🟠 **HIGH** | 4 | エラーメッセージリーク、User Enumeration、暗号化不足 |
| 🟡 **MEDIUM** | 5 | インラインスクリプト、バリデーション不足、ログ管理 |

**全体評価:** ⚠️ **本番環境デプロイ不可。複数の致命的脆弱性が存在します**

---

## 🔴 CRITICAL 脆弱性

### 1. 認証の完全なバイパス（AUTH_BYPASS）

**ファイル:** [admin-auth.js](admin-auth.js#L46-L50)

**現在の実装:**
```javascript
async function ensureAuthenticated(supabaseClient, redirectUrl = 'index.html', policy = {}) {
    // AUTH_BYPASS_START — 認証を一時停止中。本番環境では復元が必須。
    // ローカル開発・テスト用に認証をスキップします
    return true;
    // AUTH_BYPASS_END
}
```

**脅威:** 全ての管理画面（admin-*.html）が認証なしでアクセス可能  
**影響度:** 🔴 **CRITICAL** - 全管理機能への無制限アクセス

**修正前後コード:**

修正前：
```javascript
async function ensureAuthenticated(supabaseClient, redirectUrl = 'index.html', policy = {}) {
    return true; // ← 常に認証成功を返す
}
```

修正後：
```javascript
async function ensureAuthenticated(supabaseClient, redirectUrl = 'index.html', policy = {}) {
    if (!supabaseClient) {
        window.location.href = redirectUrl;
        return false;
    }

    try {
        const { data: { user }, error } = await supabaseClient.auth.getUser();
        
        if (error || !user) {
            window.location.href = redirectUrl;
            return false;
        }

        const policy_obj = getDefaultPolicy();
        if (!isAdminAuthorized(user, policy_obj)) {
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
```

---

### 2. CORS ワイルドカード設定（ "$*" 検証不足）

**ファイル:** 複数のEdge Functions
- [send-contact-mail/index.ts](supabase/functions/send-contact-mail/index.ts#L3-L5)
- [send-application-mail/index.ts](supabase/functions/send-application-mail/index.ts#L3-L5)
- [send-meeting-invite-mail/index.ts](supabase/functions/send-meeting-invite-mail/index.ts#L3-L5)

**現在の実装:**
```typescript
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
```

**脅威:** 
- 任意のオリジンからのリクエスト受け入れ
- CSRF（クロスサイトリクエストフォージェリ）攻撃の可能性
- 外部サイトからメール送信機能の悪用

**修正前後コード:**

修正前：
```typescript
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",  // ← 危険
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
```

修正後（send-contact-mail/index.tsの例）：
```typescript
function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") || "";
  const allowedOrigins = [
    "https://cidm-website.example.com",
    "http://localhost:3000",  // 開発環境用
  ];
  
  const isAllowed = allowedOrigins.includes(origin);
  
  return {
    "Access-Control-Allow-Origin": isAllowed ? origin : "null",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
}

serve(async (req: Request) => {
  const corsHeaders = getCorsHeaders(req);
  
  if (req.method === "OPTIONS") {
    return new Response("ok", { 
      status: 204,
      headers: corsHeaders 
    });
  }
  
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: corsHeaders,
    });
  }
  // ... rest of code
});
```

---

### 3. セッション管理の脆弱性（sessionStorage 使用）

**ファイル:** [index.html](index.html#L335-L340), [member.html](member.html#L173-L180)

**現在の実装:**
```javascript
// ログイン時
sessionStorage.setItem(MEMBER_AUTH_KEY, '1');
sessionStorage.setItem(MEMBER_ID_KEY, member.login_id || loginId);
sessionStorage.setItem(MEMBER_NAME_KEY, member.staff_name || '');
sessionStorage.setItem(MEMBER_COMPANY_KEY, member.company_name || '');
window.location.href = 'member.html';

// member.html側
const memberId = sessionStorage.getItem(MEMBER_ID_KEY) || '';
const memberName = sessionStorage.getItem(MEMBER_NAME_KEY) || '';
```

**脅威:**
- JavaScriptで個人情報がアクセス可能（XSS脆弱性の場合）
- ブラウザディベロッパーツールで平文で確認可能
- ページリロード後も検証なしで信頼される
- セッション盗難が容易

**修正前後コード:**

修正前：
```javascript
sessionStorage.setItem(MEMBER_ID_KEY, member.login_id);  // 平文保存
```

修正後（推奨: HttpOnly Cookie + サーバー側セッション検証）：
```javascript
// フロントエンド側: Edge Functionでセッション作成
const response = await fetch(LOGIN_EDGE_FUNCTION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',  // Cookie送信を有効化
    body: JSON.stringify({ login_id: loginId, password })
});

// サーバー側設定: set-cookie ヘッダーで HttpOnly Cookie を返す
if (!response.ok) {
    const errorData = await response.json();
    throw new Error(errorData.error || 'Login failed');
}

// セッション検証用の Supabase session token を使用
const { session } = await response.json();
// Note: Supabaseの auth.session は自動でHttpOnlyで管理される
```

---

## 🟠 HIGH 脆弱性

### 4. エラーメッセージからの情報漏洩

**ファイル:** [index.html](index.html#L270-L282)

**現在の実装:**
```javascript
catch (e) {
    let message = e.message || 'ログインに失敗しました。';
    if (message.toLowerCase().includes('invalid login credentials')) {
        message = 'メールアドレスまたはパスワードが正しくありません。';
    } else if (message.toLowerCase().includes('email not confirmed')) {
        message = 'メール確認が未完了です。';
    }
    window.cidmAdminUi.showToast('ログイン失敗: ' + message, 'error', 3600);
}
```

**脅威:**
- User Enumeration attack: 存在するメールアドレスを推測可能
- エラーメッセージから認証プロセスの詳細を把握可
- 攻撃者が有効なアカウントを特定可能

**修正前後コード:**

修正前：
```javascript
if (message.toLowerCase().includes('invalid login credentials')) {
    message = 'メールアドレスまたはパスワードが正しくありません。';  // ← 差別化
} else if (message.toLowerCase().includes('email not confirmed')) {
    message = 'メール確認が未完了です。';  // ← 存在確認
}
```

修正後：
```javascript
catch (e) {
    // 全ての失敗を同じメッセージで統一（User Enumeration防止）
    window.cidmAdminUi.showToast('メールアドレスまたはパスワードが正しくありません。', 'error', 2600);
    
    // サーバー側ログに詳細記録
    console.error('[AUTH_FAILED]', {
        timestamp: new Date().toISOString(),
        email: email,  // 本番環境では記録しない
        error: e.message,
        userAgent: navigator.userAgent,
    });
}
```

---

### 5. パスワード最小文字数の不十分な強度

**ファイル:** [supabase/migrations/20260410_member_login.sql](supabase/migrations/20260410_member_login.sql#L70-L72)

**現在の実装:**
```sql
if v_password is not null and length(v_password) < 8 then
    raise exception 'password must be at least 8 characters';
end if;
```

**脅威:** 8文字は現代のセキュリティー基準として不十分（NIST推奨: 最小12文字）

**修正前後コード:**

修正前：
```sql
if v_password is not null and length(v_password) < 8 then
    raise exception 'password must be at least 8 characters';
end if;
```

修正後：
```sql
if v_password is not null then
    if length(v_password) < 12 then
        raise exception 'password must be at least 12 characters';
    end if;
    
    -- 複雑性チェック（大文字、小文字、数字、記号を最低1文字ずつ含む）
    if not (v_password ~ '[A-Z]' and v_password ~ '[a-z]' and v_password ~ '[0-9]') then
        raise exception 'password must contain uppercase, lowercase, and numbers';
    end if;
end if;
```

HTMLのパスワード入力フィールドも更新：
```html
<!-- 修正前 -->
<input type="password" id="initial_password" name="initial_password" required minlength="8" placeholder="8文字以上">

<!-- 修正後 -->
<input type="password" id="initial_password" name="initial_password" required minlength="12" 
       pattern="^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)[A-Za-z\d@$!%*?&]{12,}$"
       placeholder="12文字以上（大小文字、数字を含む）" 
       title="12文字以上の大小文字、数字を含むパスワードを入力してください">
```

---

### 6. パスワード表示/非表示トグルのUX vs セキュリティー問題

**ファイル:** [admin-member-edit.html](admin-member-edit.html#L126-L138), [admin-member-new.html](admin-member-new.html#L140-L152)

**現在の実装:**
```html
<button type="button" id="member-password-toggle" 
        style="...">表示</button>
```

**脅威:** 近くの他者がパスワードを覗き見て盗聴される可能性

**推奨対策:**

修正前後コード：

修正前：
```javascript
memberPasswordToggle?.addEventListener('click', () => {
    const isPassword = memberPasswordInput?.type === 'password';
    if (!memberPasswordInput) return;
    memberPasswordInput.type = isPassword ? 'text' : 'password';  // ← 平文表示
    memberPasswordToggle.textContent = isPassword ? '非表示' : '表示';
});
```

修正後（推奨: 表示機能の廃止またはパスワード再生成）：
```javascript
// Option 1: 「パスワード再設定」ページに遷移
memberPasswordToggle?.addEventListener('click', () => {
    window.location.href = 'admin-member-password-reset.html?id=' + memberId;
});

// Option 2: 表示機能を廃止し、「パスワード再設定」ボタンのみ
<!-- ボタンのテキスト変更 -->
<button type="button" id="member-password-reset-btn" class="btn btn-secondary">
    パスワード再設定
</button>
```

---

## 🟡 MEDIUM 脆弱性

### 7. インラインスクリプト（CSP違反のリスク）

**ファイル:** 複数のHTMLファイル（全admin-*.html）

**現在:** HTMLに直接JavaScriptコードが埋め込まれている

**脅威:** 
- CSP（Content Security Policy）を厳格に設定できない
- インラインスクリプトインジェクション攻撃のリスク

**修正案:** 全ての `<script>` タグをHTMLから分離

```html
<!-- 修正前（admin-member-new.html の例） -->
<script>
    const supabaseClient = window.cidmAdminAuth.createSupabaseClient();
    // ... 数百行のコード ...
</script>

<!-- 修正後 -->
<script src="./js/admin-member-new.js"></script>
<!-- CSPヘッダーで許可 -->
<!-- Content-Security-Policy: script-src 'self'; default-src 'self'; img-src 'self' https://... -->
```

---

### 8. XSS対策の不完全性（escapeHtml関数の限界）

**ファイル:** [member.html](member.html#L227-L235), [admin-events.html](admin-events.html#L189-L210)

**現在の実装:**
```javascript
function escapeHtml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// 使用箇所の一部
container.innerHTML = items.map((item) => `
    <a href="${escapeHtml(item.file_url)}" target="_blank">
        ${escapeHtml(item.title || '名称未設定')}
    </a>
`).join('');
```

**脅威:**
- 不正なURL（`javascript:`や`data:`プロトコル）の防止が不十分
- DOMPurifyライブラリが推奨されているが未導入

**修正前後コード:**

修正前：
```javascript
<a href="${escapeHtml(item.file_url)}" target="_blank">  // javascript: は完全に防げない
```

修正後（推奨案）：
```html
<!-- HTMLヘッダに DOMPurify を追加 -->
<script src="https://cdn.jsdelivr.net/npm/dompurify@3.0.6/dist/purify.min.js"></script>

<script>
// セーフなURL判定関数
function isSafeUrl(url) {
    try {
        const parsed = new URL(url, window.location.href);
        return parsed.protocol === 'http:' || parsed.protocol === 'https:' || parsed.protocol === 'file:';
    } catch {
        return false;
    }
}

function renderDocuments(items) {
    const container = document.getElementById('member-doc-list');
    if (!container) return;

    container.innerHTML = items.map((item) => {
        const href = isSafeUrl(item.file_url) ? item.file_url : '#';
        const title = DOMPurify.sanitize(item.title || '名称未設定', { ALLOWED_TAGS: [] });
        const fileType = DOMPurify.sanitize(item.file_type || 'FILE', { ALLOWED_TAGS: [] });
        
        return `<a href="${escapeHtml(href)}" target="_blank" rel="noopener noreferrer">
            ${title}
            <p class="text-sm">${fileType}</p>
        </a>`;
    }).join('');
}
</script>
```

---

### 9. ファイルアップロード検証の不完全性

**ファイル:** [admin-topic-edit.html](admin-topic-edit.html#L149-L158)

**現在の実装:**
```javascript
function isAllowedFile(file) {
    const type = String(file.type || '').toLowerCase();
    if (ALLOWED_MIME_EXACT.includes(type)) return true;
    if (ALLOWED_MIME_PREFIX.some((p) => type.startsWith(p))) return true;
    const lowerName = String(file.name || '').toLowerCase();
    return ALLOWED_EXT.some((ext) => lowerName.endsWith(ext));
}
```

**脅威:**
- MIME typeはクライアント側から改ざん可能
- ファイル拡張子による判定は信頼できない
- 実ファイル型式（マジックバイト）の検証がない

**修正案:**

修正前後コード：

修正前：
```javascript
// MIMEタイプのみで判定（改ざん可能）
if (ALLOWED_MIME_EXACT.includes(type)) return true;
```

修正後（サーバー側検証を追加）：
```javascript
// フロントエンド側: 基本的なチェック（UX向上用）
function isAllowedFile(file) {
    const type = file.type?.toLowerCase() || '';
    const name = file.name?.toLowerCase() || '';
    
    // ファイルサイズチェック（例: 10MB以下）
    if (file.size > 10 * 1024 * 1024) {
        throw new Error('ファイルサイズは10MB以下にしてください');
    }
    
    // ファイル拡張子による基本フィルタ
    const allowedExts = ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.jpg', '.png'];
    const hasAllowedExt = allowedExts.some(ext => name.endsWith(ext));
    
    if (!hasAllowedExt) {
        throw new Error('許可されていないファイル形式です');
    }
    
    return true;
}

// サーバー側検証: Edge Function で実施
// supabase/functions/upload-file/index.ts
const buffer = await file.arrayBuffer();
const uint8 = new Uint8Array(buffer);

// マジックバイトチェック（例: PDF, JPEG）
const pdfMagic = [0x25, 0x50, 0x44, 0x46];  // %PDF
const jpegMagic = [0xFF, 0xD8, 0xFF];        // JPEG

if (isValidMagic(uint8, pdfMagic) || isValidMagic(uint8, jpegMagic)) {
    // 許可
} else {
    throw new Error('ファイル形式が無効です');
}
```

---

### 10. ロギングとモニタリングの欠落

**脅威:** セキュリティーインシデント発生時に痕跡が残らない

**推奨修正:**

```typescript
// Edge Function 共通ロギング関数を作成
// supabase/functions/shared/logging.ts

export async function logSecurityEvent(
    eventType: string,
    details: Record<string, unknown>,
    supabaseClient: any
) {
    try {
        await supabaseClient.from('security_audit_logs').insert({
            event_type: eventType,
            timestamp: new Date().toISOString(),
            details: JSON.stringify(details),
            ip_address: getClientIp(),  // リクエストから取得
            user_agent: null,  // ログには記録しない
        });
    } catch (e) {
        // ログ出力の失敗はキャッチして続行
        console.error('Failed to log security event:', e);
    }
}

// 使用例: login-admin/index.ts
export default async function handler(req: Request): Promise<Response> {
    try {
        const { email, password } = await req.json();
        
        // ログイン試行を記録
        await logSecurityEvent('LOGIN_ATTEMPT', {
            email: email,  // 本番環境では除外
            success: false,
            timestamp: new Date().toISOString(),
        }, supabase);
        
        // ... ログイン処理 ...
    } catch (e) {
        await logSecurityEvent('LOGIN_ERROR', {
            error: e.message,
            timestamp: new Date().toISOString(),
        }, supabase);
    }
}
```

---

## ✅ 優れている点

### 1. ✓ パスワード暗号化（bcrypt使用）
**ファイル:** [20260410_member_login.sql](supabase/migrations/20260410_member_login.sql#L95-L97)

```sql
password_hash = extensions.crypt(v_password, extensions.gen_salt('bf'))
```

bcrypt（cost factor = default 8）を使用しているため、パスワード保存は安全。

### 2. ✓ RLS（Row Level Security）の実装
**ファイル:** [20260410_rls_baseline.sql](supabase/migrations/20260410_rls_baseline.sql)

管理表示、一般会員の行単位アクセス制御が実装されている。

### 3. ✓ SQL インジェクション対策
Supabase ORMおよびパラメータ化クエリを使用。直接SQLクエリの発行がない。

### 4. ✓ XSS対策（部分的）
escapeHtml関数により基本的なHTMLタグのエスケープを実施。

---

## 📋 修正優先順位

### Phase 1: 本番環境デプロイ前に必ず修正（1～3週間）
1. **AUTH_BYPASS を削除** ← 最優先
2. **CORS: wildcard設定を修正**
3. **sessionStorage をサーバー側セッションに変更**
4. **エラーメッセージを平文化**

### Phase 2: セキュリティー強化（1ヶ月～）
5. パスワード複雑性ルール追加
6. インラインスクリプト外部化 + CSP設定
7. ファイルアップロード: サーバー側マジックバイト検証
8. DOMPurify ライブラリ導入
9. ロギング・監査ログ実装

### Phase 3: 継続的改善（本番稼働後）
10. 定期的なペネトレーションテスト
11. セキュリティーヘッダー（STS、X-Frame-Options等）設定
12. WAF（Web Application Firewall）導入
13. レート制限・DDoS対策

---

## 🔒 セキュリティーチェックリスト

```
[ ] AUTH_BYPASS コード削除
[ ] CORS: オリジン制限設定
[ ] sessionStorage → HttpOnly Cookie + サーバー側検証
[ ] エラーメッセージ統一
[ ] パスワード最小12文字 + 複雑性チェック
[ ] インラインスクリプト外部化
[ ] CSP ヘッダー設定
[ ] DOMPurify 導入
[ ] ファイルアップロード: マジックバイト検証
[ ] ロギング・監査ログ テーブル作成
[ ] Security Headers 設定（X-Frame-Options, X-Content-Type-Options等）
[ ] HTTPSの強制化
[ ] レート制限実装
[ ] 定期的なセキュリティー監査スケジュール化
```

---

## 📚 参考リソース

- **OWASP Top 10:** https://owasp.org/www-project-top-ten/
- **NIST Password Guidelines:** https://pages.nist.gov/800-63-3/sp800-63b.html
- **Content Security Policy:** https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP
- **Supabase Security Best Practices:** https://supabase.com/docs/guides/auth
