import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

const corsHeaders = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey'
}

function normalizeLoginId(value: string): string {
  return String(value || '').trim()
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value)
  const hash = await crypto.subtle.digest('SHA-256', data)
  const bytes = Array.from(new Uint8Array(hash))
  return bytes.map((b) => b.toString(16).padStart(2, '0')).join('')
}

async function sendResetEmail(to: string, resetUrl: string): Promise<void> {
  const resendApiKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('RESEND_FROM_EMAIL')

  if (!resendApiKey || !from) {
    throw new Error('Missing mail settings')
  }

  const subject = '【CIDM】会員パスワード再設定のご案内'
  const text = [
    '会員サイトのパスワード再設定リクエストを受け付けました。',
    '以下のURLから新しいパスワードを設定してください。',
    '',
    resetUrl,
    '',
    'このリンクの有効期限は30分です。',
    '心当たりがない場合は、このメールを破棄してください。'
  ].join('\n')

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      text
    })
  })

  if (!response.ok) {
    const body = await response.text()
    throw new Error(body || 'Failed to send email')
  }
}

async function handleRequest(loginId: string, origin?: string): Promise<Response> {
  const normalized = normalizeLoginId(loginId)
  if (!normalized) {
    return new Response(JSON.stringify({ error: 'login_id is required' }), {
      status: 400,
      headers: corsHeaders
    })
  }

  const { data: members, error } = await supabase
    .from('member')
    .select('id, email, staff_email')
    .or(`login_id.eq.${normalized},email.eq.${normalized},staff_email.eq.${normalized}`)
    .limit(1)

  if (error) {
    return new Response(JSON.stringify({ error: 'request failed' }), {
      status: 500,
      headers: corsHeaders
    })
  }

  const member = Array.isArray(members) ? members[0] : null
  if (member) {
    const email = String(member.staff_email || member.email || '').trim()
    if (email) {
      try {
        const token = crypto.randomUUID().replace(/-/g, '') + crypto.randomUUID().replace(/-/g, '')
        const tokenHash = await sha256Hex(token)

        const { error: markOldError } = await supabase
          .from('member_password_reset_tokens')
          .update({ used_at: new Date().toISOString() })
          .eq('member_id', member.id)
          .is('used_at', null)

        if (markOldError) {
          console.warn('mark old tokens warning:', markOldError.message)
        }

        const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString()
        const { error: insertError } = await supabase
          .from('member_password_reset_tokens')
          .insert([{ member_id: member.id, token_hash: tokenHash, expires_at: expiresAt }])

        if (insertError) {
          throw insertError
        }

        const base = origin && /^https?:\/\//.test(origin)
          ? origin.replace(/\/$/, '')
          : 'https://cidm2007.github.io'
        const resetUrl = `${base}/cidm-website/index.html?memberResetToken=${encodeURIComponent(token)}`

        await sendResetEmail(email, resetUrl)
      } catch (requestError) {
        console.error('password reset request error:', requestError)
      }
    }
  }

  // Prevent account enumeration: always return success.
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: corsHeaders
  })
}

async function handleReset(token: string, newPassword: string): Promise<Response> {
  const rawToken = String(token || '').trim()
  if (!rawToken) {
    return new Response(JSON.stringify({ error: 'token is required' }), {
      status: 400,
      headers: corsHeaders
    })
  }

  if (!newPassword || newPassword.length < 8) {
    return new Response(JSON.stringify({ error: 'password must be at least 8 characters' }), {
      status: 400,
      headers: corsHeaders
    })
  }

  const tokenHash = await sha256Hex(rawToken)
  const { data, error } = await supabase.rpc('cidm_consume_member_password_reset', {
    p_token_hash: tokenHash,
    p_new_password: newPassword
  })

  if (error) {
    return new Response(JSON.stringify({ error: 'reset failed' }), {
      status: 500,
      headers: corsHeaders
    })
  }

  if (!data) {
    return new Response(JSON.stringify({ error: 'token invalid or expired' }), {
      status: 400,
      headers: corsHeaders
    })
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: corsHeaders
  })
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      status: 200,
      headers: corsHeaders
    })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: corsHeaders
    })
  }

  try {
    const body = await req.json()
    const action = String(body?.action || '').trim()

    if (action === 'request') {
      return await handleRequest(String(body?.login_id || ''), String(body?.origin || ''))
    }

    if (action === 'reset') {
      return await handleReset(String(body?.token || ''), String(body?.new_password || ''))
    }

    return new Response(JSON.stringify({ error: 'invalid action' }), {
      status: 400,
      headers: corsHeaders
    })
  } catch (error) {
    console.error('member password reset error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: corsHeaders
    })
  }
}
