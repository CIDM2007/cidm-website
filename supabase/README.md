# Supabase運用メモ（CIDM）

## 追加済みマイグレーション

- `supabase/migrations/20260410_rls_baseline.sql`

## 適用手順

1. Supabase CLIを利用可能にする

```powershell
npx supabase --version
```

2. Supabaseアカウントへログイン

```powershell
npx supabase login
```

3. プロジェクトをリンク

```powershell
npx supabase link --project-ref uhhhifbotqidqeceqyis
```

4. マイグレーションを反映

```powershell
npx supabase db push --linked --yes
```

## チーム向け: migration 作成テンプレート（PowerShell）

重複しない 14 桁タイムスタンプ（`yyyyMMddHHmmss`）で migration を作るため、
次のテンプレートを追加しています。

- `supabase/new-migration.ps1`

### 使い方

```powershell
./supabase/new-migration.ps1 -Name "harden_admin_policy"
```

作成されるファイル名の例:

- `supabase/migrations/20260421123045_harden_admin_policy.sql`

### Dry Run（作成せずコマンドだけ確認）

```powershell
./supabase/new-migration.ps1 -Name "add_member_index" -DryRun
```

### 作成後の標準手順

```powershell
npx supabase db push --linked --dry-run --yes
npx supabase db push --linked --yes
```

## 会員Authユーザーの一括作成（member -> auth.users）

`member.auth_user_id` が未リンクの会員を対象に、`login_id` メールで `auth.users` を作成し、
作成後に `member.auth_user_id` を再リンクするスクリプトを追加しています。

- `supabase/provision-member-auth-users.ps1`

### Dry Run（対象確認のみ）

```powershell
./supabase/provision-member-auth-users.ps1 -Limit 5 -DryRun
```

### 実行（5件のパイロット）

```powershell
$env:SUPABASE_URL = 'https://uhhhifbotqidqeceqyis.supabase.co'
$env:SUPABASE_SERVICE_ROLE_KEY = '<legacy-service-role-jwt>'
./supabase/provision-member-auth-users.ps1 -Limit 5
```

### 全件実行

```powershell
$env:SUPABASE_URL = 'https://uhhhifbotqidqeceqyis.supabase.co'
$env:SUPABASE_SERVICE_ROLE_KEY = '<legacy-service-role-jwt>'
./supabase/provision-member-auth-users.ps1 -All
```

注意:

- `SUPABASE_SERVICE_ROLE_KEY` は機密情報です。共有やコミットはしないでください。
- このスクリプトは `/auth/v1/admin/users` を直接呼ぶため、`sb_secret_...` ではなく JWT 形式の legacy `service_role` キーが必要です。
- スクリプトはランダムパスワードでユーザーを作成し、`email_confirm=true` で登録します。
- 作成後に `member.auth_user_id` をメール一致で更新します。

## legacy JWT キー無効化に向けた設定方針

- フロントエンド: `cidm-config.js` の `window.CIDM_SUPABASE_PUBLISHABLE_KEY` に `sb_publishable_...` を設定
- 互換用に `window.CIDM_SUPABASE_ANON_KEY` は `CIDM_SUPABASE_PUBLISHABLE_KEY` の別名として残している
- Edge Functions: `SUPABASE_SECRET_KEY` を優先して読むよう調整済み。未移行環境では `SUPABASE_SERVICE_ROLE_KEY` にフォールバック

## 現在のブロッカー

このワークスペースで `npx supabase link --project-ref uhhhifbotqidqeceqyis` を実行したところ、
次のエラーで停止しました。

- `Your account does not have the necessary privileges to access this endpoint`

必要な対処:

- 対象 Supabase プロジェクトに対する適切な権限（Owner / Admin 相当）を付与
- もしくは権限を持つアカウントで `npx supabase login` を実行してから再試行

## チェックポイント（反映後）

- meeting_reports:
  - `is_visible = true` の公開データが匿名で閲覧可能
  - 管理者のみ作成・更新・削除可能
- applications:
  - 匿名/認証問わず insert のみ可能
  - read/update/delete は不可
- member:
  - 管理者のみ CRUD 可能
- member_documents:
  - 現行実装では匿名閲覧可
  - 追加/更新/削除は管理者のみ

## ログインIDをメールアドレスへ統一（20260610000200）

対象 migration:

- `supabase/migrations/20260610000200_enforce_member_login_email_only.sql`

### 反映前チェック（重複メール確認）

`login_id` はユニーク制約があるため、会員 `email` が重複していると正規化更新で失敗する可能性があります。

```sql
select lower(btrim(email)) as normalized_email, count(*) as cnt
from public.member
where nullif(btrim(coalesce(email, '')), '') is not null
group by lower(btrim(email))
having count(*) > 1
order by cnt desc, normalized_email;
```

上記結果が0件であることを確認してから `db push` を実行してください。

### 反映後チェック（動作確認）

```sql
-- 1) login_id が email と一致しているか
select id, login_id, email
from public.member
where nullif(btrim(coalesce(email, '')), '') is not null
  and lower(btrim(coalesce(login_id, ''))) <> lower(btrim(email));

-- 2) login_id がメール形式違反になっていないか
select id, login_id
from public.member
where nullif(btrim(coalesce(login_id, '')), '') is not null
  and lower(btrim(login_id)) !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}$';
```

どちらも0件になることを確認してください。
