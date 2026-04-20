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
    const { login_id, password } = await req.json()

    if (!login_id || !password) {
      return new Response(JSON.stringify({ error: 'Missing login_id or password' }), {
        status: 400,
        headers: corsHeaders
      })
    }

    const { data, error } = await supabase.rpc('cidm_member_login', {
      p_login_id: login_id,
      p_password: password
    })

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 401,
        headers: corsHeaders
      })
    }

    const member = Array.isArray(data) ? data[0] : null
    if (!member) {
      return new Response(JSON.stringify({ error: 'Invalid credentials' }), {
        status: 401,
        headers: corsHeaders
      })
    }

    return new Response(JSON.stringify({
      login_id: member.login_id,
      staff_name: member.staff_name,
      company_name: member.company_name
    }), {
      status: 200,
      headers: corsHeaders
    })
  } catch (error) {
    console.error('Error logging in member:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: corsHeaders
    })
  }
}