import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// member-password-reset Edge Function
// action=request  : 担当者が自分でリセット要求（セルフサービス）
// action=consume  : トークンを使ってパスワード設定（担当者・旧会員両対応）
// action=invite   : 管理者が担当者を招待（招待メール送信）

const SUPABASE_URL = (Deno.env.get('SUPABASE_URL') || '').trim()
const SUPABASE_SERVICE_ROLE_KEY = (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '').trim()

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

const corsHeaders = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey, x-client-info, x-supabase-api-version'
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders
  })
}

function normalizeEmail(value: unknown): string {
  return String(value || '').trim().toLowerCase()
}

function isValidEmail(value: string): boolean {
  return /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}$/i.test(value)
}

function createRawToken(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('')
  return `${crypto.randomUUID()}${hex}`
}

async function sha256Hex(value: string): Promise<string> {
  const encoded = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', encoded)
  const bytes = new Uint8Array(digest)
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('')
}

function buildResetUrl(req: Request, token: string): string {
  const configuredBase = String(Deno.env.get('MEMBER_PASSWORD_RESET_URL_BASE') || '').trim()
  const origin = (req.headers.get('origin') || '').trim().replace(/\/$/, '')
  const base = configuredBase || (origin ? `${origin}/member-password-reset.html` : '')
  if (!base) {
    throw new Error('MEMBER_PASSWORD_RESET_URL_BASE is not configured')
  }
  const separator = base.includes('?') ? '&' : '?'
  return `${base}${separator}token=${encodeURIComponent(token)}`
}

function buildAdminRedirectUrl(req: Request, redirectTo = ''): string {
  const configuredBase = String(Deno.env.get('ADMIN_PASSWORD_RESET_URL_BASE') || '').trim()
  const origin = (req.headers.get('origin') || '').trim().replace(/\/$/, '')
  const defaultBase = origin ? `${origin}/member-password-reset.html?from=admin` : ''
  const explicitBase = String(redirectTo || '').trim()
  const base = explicitBase || configuredBase || defaultBase
  if (!base) {
    throw new Error('ADMIN_PASSWORD_RESET_URL_BASE is not configured')
  }

  return base
}

async function sendResetMail(toEmail: string, resetUrl: string): Promise<void> {
  const resendApiKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('RESEND_FROM_EMAIL')

  if (!resendApiKey || !from) {
    throw new Error('Missing email environment variables')
  }

  const subject = '【CIDM】パスワード再設定のご案内'
  const text = [
    'CIDM 会員各位',
    '',
    'パスワード再設定のお手続きをご案内いたします。',
    'お手数ですが、下記URLから新しいパスワードへの変更をお願いいたします。',
    '',
    resetUrl,
    '',
    'URLの有効期限は1時間となっております。',
    '有効期限を過ぎた場合は、お手数ですが再度お申し込みください。',
    '',
    'このメールに心当たりがない場合は、お手数ですが破棄していただければ幸いです。',
    '',
    '――――――――――――――――――',
    'CIDM',
    `送信先: ${toEmail}`
  ].join('\n')

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from,
      to: [toEmail],
      subject,
      text
    })
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(errorText || 'Failed to send reset email')
  }
}

async function sendAdminRecoveryMail(toEmail: string, recoveryUrl: string): Promise<void> {
  const resendApiKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('RESEND_FROM_EMAIL')

  if (!resendApiKey || !from) {
    throw new Error('Missing email environment variables')
  }

  const subject = '【CIDM】管理者パスワード回復のご案内'
  const text = [
    'CIDM 管理者各位',
    '',
    'パスワードの回復用のURLです。',
    'こちらのURLを押して、パスワードを回復してください。',
    '',
    recoveryUrl,
    '',
    'URLの有効期限は1時間です。',
    '有効期限を過ぎた場合は、再度お手続きをお願いいたします。',
    '',
    'このメールに心当たりがない場合は、破棄してください。',
    '',
    '――――――――――――――――――',
    '一般社団法人車両情報活用研究所：CIDM',
    `送信先: ${toEmail}`
  ].join('\n')

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from,
      to: [toEmail],
      subject,
      text
    })
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(errorText || 'Failed to send admin recovery email')
  }
}

async function requestAdminReset(req: Request, payload: Record<string, unknown>): Promise<Response> {
  const loginId = normalizeEmail(payload.login_id)
  const redirectTo = String(payload.redirect_to || '').trim()

  if (!loginId || !isValidEmail(loginId)) {
    return jsonResponse({ error: 'メールアドレスを入力してください。' }, 400)
  }

  const { data: memberRows, error: memberError } = await supabase
    .from('member')
    .select('id, app_role, login_id, email, staff_email')
    .eq('app_role', 'admin')
    .limit(500)

  if (memberError) {
    console.error('member-password-reset admin member lookup error:', memberError)
    return jsonResponse({ error: '管理者確認に失敗しました。時間をおいて再度お試しください。' }, 500)
  }

  const member = Array.isArray(memberRows)
    ? memberRows.find((row) => {
        const login = normalizeEmail(row?.login_id)
        const email = normalizeEmail(row?.email)
        const staffEmail = normalizeEmail(row?.staff_email)
        return loginId === login || loginId === email || loginId === staffEmail
      })
    : null
  if (!member) {
    return jsonResponse({ error: '管理者以外の方のログインは許可されていません。' }, 403)
  }

  const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
    type: 'recovery',
    email: loginId,
    options: {
      redirectTo: buildAdminRedirectUrl(req, redirectTo)
    }
  })

  if (linkError) {
    console.error('member-password-reset admin generateLink error:', linkError)
    return jsonResponse({ error: 'パスワード回復URLの生成に失敗しました。' }, 500)
  }

  const actionLink = String(linkData?.properties?.action_link || '').trim()
  if (!actionLink) {
    return jsonResponse({ error: 'パスワード回復URLの生成に失敗しました。' }, 500)
  }

  try {
    await sendAdminRecoveryMail(loginId, actionLink)
  } catch (mailError) {
    console.error('member-password-reset admin send mail error:', mailError)
    return jsonResponse({ error: 'メール送信に失敗しました。時間をおいて再度お試しください。' }, 500)
  }

  return jsonResponse({ ok: true })
}

// -------------------------------------------------------
// action=request: 担当者セルフサービス パスワードリセット要求
// -------------------------------------------------------
async function requestReset(req: Request, payload: Record<string, unknown>): Promise<Response> {
  const loginId = normalizeEmail(payload.login_id)

  if (!loginId || !isValidEmail(loginId)) {
    return jsonResponse({ ok: true })
  }

  const rawToken = createRawToken()
  const tokenHash = await sha256Hex(rawToken)

  // 担当者（member_staff_auth）から検索
  const { data: rows, error: rpcError } = await supabase.rpc(
    'cidm_request_contact_password_reset',
    { p_login_id: loginId, p_token_hash: tokenHash }
  )

  if (rpcError) {
    console.error('member-password-reset contact request error:', rpcError)
    return jsonResponse({ error: 'Internal server error' }, 500)
  }

  const contact = Array.isArray(rows) ? rows[0] : null

  // 見つからない場合は成功扱い（列挙攻撃防止）
  if (!contact || !contact.contact_email) {
    return jsonResponse({ ok: true })
  }

  try {
    const resetUrl = buildResetUrl(req, rawToken)
    await sendResetMail(contact.contact_email, resetUrl)
  } catch (mailError) {
    console.error('member-password-reset send mail error:', mailError)
    return jsonResponse({ error: 'メール送信に失敗しました。時間をおいて再度お試しください。' }, 500)
  }

  return jsonResponse({ ok: true })
}

// -------------------------------------------------------
// action=invite: 管理者が担当者に招待メールを送信
// -------------------------------------------------------
async function inviteContact(req: Request, payload: Record<string, unknown>): Promise<Response> {
  const contactId = String(payload.contact_id || '').trim()
  if (!contactId) {
    return jsonResponse({ error: 'contact_id is required' }, 400)
  }

  const authHeader = (req.headers.get('Authorization') || req.headers.get('authorization') || '').trim()
  if (!authHeader.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  // ユーザーの JWT を使ってクライアントを作成（RLS・admin チェックが機能する）
  const ANON_KEY = (Deno.env.get('SUPABASE_ANON_KEY') || '').trim()
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false }
  })

  const rawToken = createRawToken()
  const tokenHash = await sha256Hex(rawToken)

  const { data: rows, error: rpcError } = await userClient.rpc(
    'cidm_admin_create_contact_invite',
    {
      p_contact_id: contactId,
      p_token_hash: tokenHash,
      p_token_type: 'invite'
    }
  )

  if (rpcError) {
    console.error('invite contact rpc error:', rpcError)
    return jsonResponse({ error: rpcError.message || 'Internal server error' }, 500)
  }

  const row = Array.isArray(rows) ? rows[0] : null
  if (!row || !row.contact_email) {
    return jsonResponse({ error: 'contact not found or has no email' }, 400)
  }

  const inviteUrl = buildResetUrl(req, rawToken)

  try {
    await sendInviteMail(row.contact_email, row.contact_name || '', inviteUrl)
  } catch (mailError) {
    console.error('invite mail error:', mailError)
    return jsonResponse({ error: 'メール送信に失敗しました。' }, 500)
  }

  return jsonResponse({ ok: true, contact_email: row.contact_email })
}

async function sendInviteMail(toEmail: string, contactName: string, inviteUrl: string): Promise<void> {
  const resendApiKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('RESEND_FROM_EMAIL')
  if (!resendApiKey || !from) throw new Error('Missing email environment variables')

  const subject = '【CIDM】会員ポータル ログイン情報のご案内'
  const text = [
    contactName ? `${contactName} 様` : 'CIDM 会員担当者様',
    '',
    'このたびは CIDM 会員ポータルへのログイン情報をお送りします。',
    '以下の URL からパスワードを設定のうえ、ポータルへのログインをお願いいたします。',
    '',
    inviteUrl,
    '',
    '※ このURLの有効期限は 72 時間です。期限を過ぎた場合は管理者までお問い合わせください。',
    '',
    'このメールに心当たりがない場合は、恐れ入りますが破棄してください。',
    '',
    '――――――――――――――――――',
    '一般社団法人車両情報活用研究所：CIDM',
    `送信先: ${toEmail}`
  ].join('\n')

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${resendApiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from, to: [toEmail], subject, text })
  })
  if (!res.ok) {
    const errText = await res.text()
    throw new Error(errText || 'Failed to send invite email')
  }
}

// -------------------------------------------------------
// action=consume: トークンを消費してパスワードを設定
//   担当者トークン（contact_password_reset_tokens）を優先して試みる
// -------------------------------------------------------
async function consumeReset(payload: Record<string, unknown>): Promise<Response> {
  const token = String(payload.token || '').trim()
  const newPassword = String(payload.new_password || '')
  const confirmPassword = String(payload.confirm_password || '')

  if (!token) {
    return jsonResponse({ error: 'token is required' }, 400)
  }

  if (!newPassword || newPassword.length < 8) {
    return jsonResponse({ error: 'password must be at least 8 characters' }, 400)
  }

  if (newPassword !== confirmPassword) {
    return jsonResponse({ error: 'password confirmation does not match' }, 400)
  }

  const tokenHash = await sha256Hex(token)

  // 担当者トークンを優先して試みる
  const { data: contactResult, error: contactError } = await supabase.rpc(
    'cidm_consume_contact_password_reset',
    { p_token_hash: tokenHash, p_new_password: newPassword }
  )

  if (!contactError && contactResult?.ok === true) {
    return jsonResponse({ ok: true })
  }

  // 担当者トークンで "invalid or expired token" 以外のエラーは内部エラー
  if (contactError) {
    console.error('member-password-reset consume contact rpc error:', contactError)
    return jsonResponse({ error: 'パスワード更新に失敗しました。' }, 400)
  }

  // contactResult.ok === false の場合: トークンが見つからなかった
  // 旧 member トークンにフォールバック（後方互換）
  const { data: memberResult, error: memberError } = await supabase.rpc(
    'cidm_consume_member_password_reset',
    { p_token_hash: tokenHash, p_new_password: newPassword }
  )

  if (memberError) {
    console.error('member-password-reset consume member rpc error:', memberError)
    return jsonResponse({ error: 'パスワード更新に失敗しました。' }, 400)
  }

  if (!memberResult) {
    return jsonResponse({ error: 'URLが無効か有効期限切れです。' }, 400)
  }

  return jsonResponse({ ok: true })
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      status: 200,
      headers: corsHeaders
    })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  try {
    const payload = await req.json()
    const action = String(payload?.action || '').trim().toLowerCase()

    if (action === 'request') {
      return await requestReset(req, payload)
    }

    if (action === 'admin_request') {
      return await requestAdminReset(req, payload)
    }

    if (action === 'consume') {
      return await consumeReset(payload)
    }

    if (action === 'invite') {
      return await inviteContact(req, payload)
    }

    return jsonResponse({ error: 'Invalid action' }, 400)
  } catch (error) {
    console.error('member-password-reset error:', error)
    return jsonResponse({ error: 'Internal server error' }, 500)
  }
})
