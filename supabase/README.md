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
npx supabase db push
```

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
