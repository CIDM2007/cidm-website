import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

export default async function handler(req: Request): Promise<Response> {
  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey'
  }

  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers
    })
  }

  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers
    })
  }

  try {
    const { data, error } = await supabase
      .from('meeting_reports')
      .select('*')
      .eq('is_visible', true)
      .order('event_date', { ascending: false })
      .limit(5)

    if (error) throw error

    return new Response(JSON.stringify(data || []), {
      status: 200,
      headers
    })
  } catch (error) {
    console.error('Error fetching top news:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers
    })
  }
}