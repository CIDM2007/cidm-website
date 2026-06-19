import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('CIDM_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

const corsHeaders = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey'
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

async function sendResetMail(toEmail: string, resetUrl: string): Promise<void> {
  const resendApiKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('RESEND_FROM_EMAIL')

  if (!resendApiKey || !from) {
    throw new Error('Missing email environment variables')
  }

  const subject = '【CIDM】パスワード再設定のご案内'
  const text = [
    'パスワード再設定のリクエストを受け付けました。',
    '以下のURLを開き、新しいパスワードを設定してください。',
    '',
    resetUrl,
    '',
    'このURLの有効期限は1時間です。',
    'このメールに心当たりがない場合は、本メールを破棄してください。'
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

async function requestReset(req: Request, payload: Record<string, unknown>): Promise<Response> {
  const loginId = normalizeEmail(payload.login_id)

  if (!loginId || !isValidEmail(loginId)) {
    return jsonResponse({ ok: true })
  }

  const { data: member, error } = await supabase
    .from('member')
    .select('id, login_id')
    .eq('login_id', loginId)
    .limit(1)
    .maybeSingle()

  if (error) {
    console.error('member-password-reset request lookup error:', error)
    return jsonResponse({ error: 'Internal server error' }, 500)
  }

  if (!member || !member.id) {
    return jsonResponse({ ok: true })
  }

  const rawToken = createRawToken()
  const tokenHash = await sha256Hex(rawToken)
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString()

  await supabase
    .from('member_password_reset_tokens')
    .update({ used_at: new Date().toISOString() })
    .eq('member_id', member.id)
    .is('used_at', null)

  const { error: insertError } = await supabase
    .from('member_password_reset_tokens')
    .insert({
      member_id: member.id,
      token_hash: tokenHash,
      expires_at: expiresAt
    })

  if (insertError) {
    console.error('member-password-reset token insert error:', insertError)
    return jsonResponse({ error: 'Internal server error' }, 500)
  }

  try {
    const resetUrl = buildResetUrl(req, rawToken)
    await sendResetMail(loginId, resetUrl)
  } catch (mailError) {
    console.error('member-password-reset send mail error:', mailError)
    return jsonResponse({ error: 'メール送信に失敗しました。時間をおいて再度お試しください。' }, 500)
  }

  return jsonResponse({ ok: true })
}

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
  const { data, error } = await supabase.rpc('cidm_consume_member_password_reset', {
    p_token_hash: tokenHash,
    p_new_password: newPassword
  })

  if (error) {
    console.error('member-password-reset consume rpc error:', error)
    return jsonResponse({ error: 'パスワード更新に失敗しました。' }, 400)
  }

  if (!data) {
    return jsonResponse({ error: 'URLが無効か有効期限切れです。' }, 400)
  }

  return jsonResponse({ ok: true })
}

export default async function handler(req: Request): Promise<Response> {
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

    if (action === 'consume') {
      return await consumeReset(payload)
    }

    return jsonResponse({ error: 'Invalid action' }, 400)
  } catch (error) {
    console.error('member-password-reset error:', error)
    return jsonResponse({ error: 'Internal server error' }, 500)
  }
}
