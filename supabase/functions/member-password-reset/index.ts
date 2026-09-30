import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// member-password-reset Edge Function
// action=request  : 担当者が自分でリセット要求（セルフサービス）
// action=consume  : トークンを使ってパスワード設定（担当者・旧会員両対応）
// action=invite   : 管理者が担当者を招待（招待メール送信）

const SUPABASE_URL = (Deno.env.get('SUPABASE_URL') || '').trim()
const SUPABASE_SERVICE_ROLE_KEY = (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '').trim()

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

// Add any additional trusted origins (e.g. a local dev server) here.
const ALLOWED_ORIGINS = new Set([
  'https://www.cidm.or.jp',
  'https://cidm.or.jp',
])

function getCorsHeaders(origin: string): Record<string, string> {
  return {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : 'https://www.cidm.or.jp',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey, x-client-info, x-supabase-api-version',
    'Vary': 'Origin'
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200, corsHeaders: Record<string, string> = {}): Response {
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

function isStrongPassword(value: string): boolean {
  return value.length >= 12 && /[A-Z]/.test(value) && /[a-z]/.test(value) && /[0-9]/.test(value)
}

function getClientIp(req: Request): string {
  const forwardedFor = req.headers.get('x-forwarded-for') || ''
  const first = forwardedFor.split(',')[0]?.trim()
  return first || req.headers.get('cf-connecting-ip') || req.headers.get('x-real-ip') || 'unknown'
}

async function checkRateLimit(key: string, limit: number, windowSeconds: number): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('cidm_check_rate_limit', {
      p_key: key,
      p_limit: limit,
      p_window_seconds: windowSeconds
    })
    if (error) {
      console.error('rate limit check failed:', error)
      return true
    }
    return data !== false
  } catch (e) {
    console.error('rate limit check threw:', e)
    return true
  }
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

function appendQueryParam(url: string, key: string, value: string): string {
  const separator = url.includes('?') ? '&' : '?'
  return `${url}${separator}${encodeURIComponent(key)}=${encodeURIComponent(value)}`
}

function buildAdminRecoveryEntryUrl(req: Request, redirectTo: string, tokenHash: string, email: string): string {
  let url = buildAdminRedirectUrl(req, redirectTo)
  url = appendQueryParam(url, 'from', 'admin')
  url = appendQueryParam(url, 'recovery_token_hash', tokenHash)
  url = appendQueryParam(url, 'recovery_email', email)
  return url
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

async function findAdminMemberByLoginId(loginId: string): Promise<Record<string, unknown> | null> {
  const { data: memberRows, error: memberError } = await supabase
    .from('member')
    .select('id, app_role, login_id, email, staff_email')
    .eq('app_role', 'admin')
    .limit(500)

  if (memberError) {
    console.error('member-password-reset admin member lookup error:', memberError)
    throw new Error('member lookup failed')
  }

  const member = Array.isArray(memberRows)
    ? memberRows.find((row) => {
        const login = normalizeEmail((row as Record<string, unknown>)?.login_id)
        const email = normalizeEmail((row as Record<string, unknown>)?.email)
        const staffEmail = normalizeEmail((row as Record<string, unknown>)?.staff_email)
        return loginId === login || loginId === email || loginId === staffEmail
      })
    : null

  return (member as Record<string, unknown>) || null
}

async function ensureAdminMetadataByEmail(email: string): Promise<void> {
  const targetEmail = normalizeEmail(email)
  if (!targetEmail) {
    return
  }

  const { data: listData, error: listError } = await supabase.auth.admin.listUsers({
    page: 1,
    perPage: 1000
  })

  if (listError) {
    console.error('member-password-reset listUsers error:', listError)
    return
  }

  const users = Array.isArray(listData?.users) ? listData.users : []
  const targetUser = users.find((u) => normalizeEmail(u?.email) === targetEmail)
  if (!targetUser || !targetUser.id) {
    return
  }

  const existingMeta = (targetUser.app_metadata || {}) as Record<string, unknown>
  if (existingMeta.is_admin === true) {
    return
  }

  const { error: updateError } = await supabase.auth.admin.updateUserById(targetUser.id, {
    app_metadata: {
      ...existingMeta,
      is_admin: true
    }
  })

  if (updateError) {
    console.error('member-password-reset updateUserById error:', updateError)
  }
}

async function canAdminLogin(payload: Record<string, unknown>, corsHeaders: Record<string, string>): Promise<Response> {
  const loginId = normalizeEmail(payload.login_id)
  if (!loginId || !isValidEmail(loginId)) {
    return jsonResponse({ ok: true, is_admin: false }, 200, corsHeaders)
  }

  try {
    const member = await findAdminMemberByLoginId(loginId)
    return jsonResponse({ ok: true, is_admin: !!member }, 200, corsHeaders)
  } catch (_e) {
    return jsonResponse({ ok: true, is_admin: false }, 200, corsHeaders)
  }
}

async function findMemberByLoginId(loginId: string): Promise<Record<string, unknown> | null> {
  const { data: memberRows, error: memberError } = await supabase
    .from('member')
    .select('id, app_role, login_id, email, staff_email, member_type, company_name, staff_name, application_status')
    .limit(2000)

  if (memberError) {
    console.error('member-password-reset member lookup error:', memberError)
    throw new Error('member lookup failed')
  }

  const member = Array.isArray(memberRows)
    ? memberRows.find((row) => {
        const login = normalizeEmail((row as Record<string, unknown>)?.login_id)
        const email = normalizeEmail((row as Record<string, unknown>)?.email)
        const staffEmail = normalizeEmail((row as Record<string, unknown>)?.staff_email)
        return loginId === login || loginId === email || loginId === staffEmail
      })
    : null

  return (member as Record<string, unknown>) || null
}

async function memberLoginContext(req: Request, corsHeaders: Record<string, string>): Promise<Response> {
  const authHeader = (req.headers.get('Authorization') || req.headers.get('authorization') || '').trim()
  if (!authHeader.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Unauthorized' }, 401, corsHeaders)
  }

  const ANON_KEY = (Deno.env.get('SUPABASE_ANON_KEY') || '').trim()
  if (!ANON_KEY) {
    return jsonResponse({ error: 'Internal server error' }, 500, corsHeaders)
  }

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false }
  })

  const { data: userData, error: userError } = await userClient.auth.getUser()
  const loginId = normalizeEmail(userData?.user?.email)
  if (userError || !loginId) {
    return jsonResponse({ error: 'Unauthorized' }, 401, corsHeaders)
  }

  let member: Record<string, unknown> | null = null
  try {
    member = await findMemberByLoginId(loginId)
  } catch (_e) {
    return jsonResponse({ error: '会員情報の取得に失敗しました。' }, 500, corsHeaders)
  }

  if (!member) {
    return jsonResponse({ error: '会員登録情報が見つかりません。' }, 404, corsHeaders)
  }

  const status = String(member.application_status || '承認済').trim() || '承認済'
  if (status !== '承認済') {
    return jsonResponse({ error: '会員審査が未承認のためログインできません。' }, 403, corsHeaders)
  }

  return jsonResponse({
    ok: true,
    context: {
      member_id: member.id || null,
      login_id: loginId,
      member_type: String(member.member_type || ''),
      company_name: String(member.company_name || ''),
      staff_name: String(member.staff_name || ''),
      app_role: String(member.app_role || 'member')
    }
  }, 200, corsHeaders)
}

async function requestAdminReset(req: Request, payload: Record<string, unknown>, corsHeaders: Record<string, string>): Promise<Response> {
  const loginId = normalizeEmail(payload.login_id)
  const redirectTo = String(payload.redirect_to || '').trim()

  if (!loginId || !isValidEmail(loginId)) {
    return jsonResponse({ error: 'メールアドレスを入力してください。' }, 400, corsHeaders)
  }

  const clientIp = getClientIp(req)
  const [ipOk, targetOk] = await Promise.all([
    checkRateLimit(`pw_reset_admin_ip:${clientIp}`, 10, 3600),
    checkRateLimit(`pw_reset_admin_target:${loginId}`, 3, 3600)
  ])
  if (!ipOk || !targetOk) {
    return jsonResponse({ error: 'リクエストが多すぎます。しばらく時間をおいて再度お試しください。' }, 429, corsHeaders)
  }

  let member: Record<string, unknown> | null = null
  try {
    member = await findAdminMemberByLoginId(loginId)
  } catch (_e) {
    return jsonResponse({ error: '管理者確認に失敗しました。時間をおいて再度お試しください。' }, 500, corsHeaders)
  }

  if (!member) {
    return jsonResponse({ error: '管理者以外の方のログインは許可されていません。' }, 403, corsHeaders)
  }

  await ensureAdminMetadataByEmail(loginId)

  const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
    type: 'recovery',
    email: loginId,
    options: {
      redirectTo: buildAdminRedirectUrl(req, redirectTo)
    }
  })

  if (linkError) {
    console.error('member-password-reset admin generateLink error:', linkError)
    return jsonResponse({ error: 'パスワード回復URLの生成に失敗しました。' }, 500, corsHeaders)
  }

  const actionLink = String(linkData?.properties?.action_link || '').trim()
  const hashedToken = String(linkData?.properties?.hashed_token || '').trim()
  if (!actionLink) {
    return jsonResponse({ error: 'パスワード回復URLの生成に失敗しました。' }, 500, corsHeaders)
  }
  if (!hashedToken) {
    return jsonResponse({ error: 'パスワード回復URLの生成に失敗しました。' }, 500, corsHeaders)
  }

  try {
    const recoveryEntryUrl = buildAdminRecoveryEntryUrl(req, redirectTo, hashedToken, loginId)
    await sendAdminRecoveryMail(loginId, recoveryEntryUrl)
  } catch (mailError) {
    console.error('member-password-reset admin send mail error:', mailError)
    return jsonResponse({ error: 'メール送信に失敗しました。時間をおいて再度お試しください。' }, 500, corsHeaders)
  }

  return jsonResponse({ ok: true }, 200, corsHeaders)
}

// -------------------------------------------------------
// action=request: 担当者セルフサービス パスワードリセット要求
// -------------------------------------------------------
async function requestReset(req: Request, payload: Record<string, unknown>, corsHeaders: Record<string, string>): Promise<Response> {
  const loginId = normalizeEmail(payload.login_id)

  if (!loginId || !isValidEmail(loginId)) {
    return jsonResponse({ ok: true }, 200, corsHeaders)
  }

  const clientIp = getClientIp(req)
  const [ipOk, targetOk] = await Promise.all([
    checkRateLimit(`pw_reset_request_ip:${clientIp}`, 10, 3600),
    checkRateLimit(`pw_reset_request_target:${loginId}`, 3, 3600)
  ])
  if (!ipOk || !targetOk) {
    return jsonResponse({ error: 'リクエストが多すぎます。しばらく時間をおいて再度お試しください。' }, 429, corsHeaders)
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
    return jsonResponse({ error: 'Internal server error' }, 500, corsHeaders)
  }

  const contact = Array.isArray(rows) ? rows[0] : null

  // 見つからない場合は成功扱い（列挙攻撃防止）
  if (!contact || !contact.contact_email) {
    return jsonResponse({ ok: true }, 200, corsHeaders)
  }

  try {
    const resetUrl = buildResetUrl(req, rawToken)
    await sendResetMail(contact.contact_email, resetUrl)
  } catch (mailError) {
    console.error('member-password-reset send mail error:', mailError)
    return jsonResponse({ error: 'メール送信に失敗しました。時間をおいて再度お試しください。' }, 500, corsHeaders)
  }

  return jsonResponse({ ok: true }, 200, corsHeaders)
}

// -------------------------------------------------------
// action=invite: 管理者が担当者に招待メールを送信
// -------------------------------------------------------
async function inviteContact(req: Request, payload: Record<string, unknown>, corsHeaders: Record<string, string>): Promise<Response> {
  const contactId = String(payload.contact_id || '').trim()
  if (!contactId) {
    return jsonResponse({ error: 'contact_id is required' }, 400, corsHeaders)
  }

  const authHeader = (req.headers.get('Authorization') || req.headers.get('authorization') || '').trim()
  if (!authHeader.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Unauthorized' }, 401, corsHeaders)
  }

  // 管理者権限チェック
  const ANON_KEY = (Deno.env.get('SUPABASE_ANON_KEY') || '').trim()
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false }
  })
  const { data: isAdminData, error: isAdminError } = await userClient.rpc('cidm_is_admin')
  if (isAdminError || !isAdminData) {
    return jsonResponse({ error: 'admin access required' }, 403, corsHeaders)
  }

  // 担当者情報を取得
  const { data: contact, error: contactError } = await supabase
    .from('member_contacts')
    .select('id, name, email, auth_user_id')
    .eq('id', contactId)
    .single()

  if (contactError || !contact) {
    return jsonResponse({ error: 'contact not found' }, 400, corsHeaders)
  }
  if (!contact.email) {
    return jsonResponse({ error: 'contact has no email' }, 400, corsHeaders)
  }

  const redirectTo = (Deno.env.get('MEMBER_PASSWORD_RESET_URL_BASE') || '').trim()
    || `${(req.headers.get('origin') || '').trim()}/member-password-reset.html`

  let authUserId: string | undefined = contact.auth_user_id

  // まず invite を試みる（新規ユーザー）
  const { data: inviteData, error: inviteError } = await supabase.auth.admin.inviteUserByEmail(
    contact.email,
    { redirectTo }
  )

  if (inviteError) {
    // 既存ユーザーの場合はパスワードリセットリンクを生成して送信
    const isAlreadyRegistered = inviteError.message?.includes('already been registered')
      || inviteError.message?.includes('already registered')
    if (!isAlreadyRegistered) {
      console.error('invite user error:', inviteError)
      return jsonResponse({ error: inviteError.message || 'メール送信に失敗しました。' }, 500, corsHeaders)
    }

    // generateLink でリセットリンクを生成
    const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
      type: 'recovery',
      email: contact.email,
      options: { redirectTo }
    })

    if (linkError || !linkData) {
      console.error('generateLink error:', linkError)
      return jsonResponse({ error: 'メール送信に失敗しました。' }, 500, corsHeaders)
    }

    // リセットリンクを Resend で送信
    try {
      await sendInviteMail(contact.email, contact.name || '', linkData.properties?.action_link || '')
    } catch (mailError) {
      console.error('invite mail error:', mailError)
      return jsonResponse({ error: 'メール送信に失敗しました。' }, 500, corsHeaders)
    }

    authUserId = linkData.user?.id || authUserId
  } else {
    authUserId = inviteData?.user?.id || authUserId
  }

  // auth_user_id を member_contacts に保存
  if (authUserId && authUserId !== contact.auth_user_id) {
    await supabase
      .from('member_contacts')
      .update({ auth_user_id: authUserId })
      .eq('id', contactId)
  }

  return jsonResponse({ ok: true, contact_email: contact.email }, 200, corsHeaders)
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
async function consumeReset(payload: Record<string, unknown>, corsHeaders: Record<string, string>): Promise<Response> {
  const token = String(payload.token || '').trim()
  const newPassword = String(payload.new_password || '')
  const confirmPassword = String(payload.confirm_password || '')

  if (!token) {
    return jsonResponse({ error: 'token is required' }, 400, corsHeaders)
  }

  if (!isStrongPassword(newPassword)) {
    return jsonResponse({ error: 'password must be at least 12 characters and include uppercase, lowercase and a number' }, 400, corsHeaders)
  }

  if (newPassword !== confirmPassword) {
    return jsonResponse({ error: 'password confirmation does not match' }, 400, corsHeaders)
  }

  const tokenHash = await sha256Hex(token)

  // 担当者トークンを優先して試みる
  const { data: contactResult, error: contactError } = await supabase.rpc(
    'cidm_consume_contact_password_reset',
    { p_token_hash: tokenHash, p_new_password: newPassword }
  )

  if (!contactError && contactResult?.ok === true) {
    return jsonResponse({ ok: true }, 200, corsHeaders)
  }

  // 担当者トークンで "invalid or expired token" 以外のエラーは内部エラー
  if (contactError) {
    console.error('member-password-reset consume contact rpc error:', contactError)
    return jsonResponse({ error: 'パスワード更新に失敗しました。' }, 400, corsHeaders)
  }

  // contactResult.ok === false の場合: トークンが見つからなかった
  // 旧 member トークンにフォールバック（後方互換）
  const { data: memberResult, error: memberError } = await supabase.rpc(
    'cidm_consume_member_password_reset',
    { p_token_hash: tokenHash, p_new_password: newPassword }
  )

  if (memberError) {
    console.error('member-password-reset consume member rpc error:', memberError)
    return jsonResponse({ error: 'パスワード更新に失敗しました。' }, 400, corsHeaders)
  }

  if (!memberResult) {
    return jsonResponse({ error: 'URLが無効か有効期限切れです。' }, 400, corsHeaders)
  }

  return jsonResponse({ ok: true }, 200, corsHeaders)
}

Deno.serve(async (req: Request): Promise<Response> => {
  const corsHeaders = getCorsHeaders(req.headers.get('origin') || '')

  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      status: 200,
      headers: corsHeaders
    })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405, corsHeaders)
  }

  try {
    const payload = await req.json()
    const action = String(payload?.action || '').trim().toLowerCase()

    if (action === 'request') {
      return await requestReset(req, payload, corsHeaders)
    }

    if (action === 'admin_request') {
      return await requestAdminReset(req, payload, corsHeaders)
    }

    if (action === 'admin_can_login') {
      return await canAdminLogin(payload, corsHeaders)
    }

    if (action === 'member_login_context') {
      return await memberLoginContext(req, corsHeaders)
    }

    if (action === 'consume') {
      return await consumeReset(payload, corsHeaders)
    }

    if (action === 'invite') {
      return await inviteContact(req, payload, corsHeaders)
    }

    return jsonResponse({ error: 'Invalid action' }, 400, corsHeaders)
  } catch (error) {
    console.error('member-password-reset error:', error)
    return jsonResponse({ error: 'Internal server error' }, 500, corsHeaders)
  }
})
