import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

const corsHeaders = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey'
}

interface NewsItem {
  event_date: string
  category: string
  title: string
  details?: string
  detail_text?: string
  attachment_urls?: string[]
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: corsHeaders
    })
  }

  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: corsHeaders
    })
  }

  try {
    // Load news
    const { data: newsData, error: newsError } = await supabase
      .from('meeting_reports')
      .select('event_date, category, title, details, detail_text, attachment_urls')
      .eq('is_visible', true)
      .order('event_date', { ascending: false })
      .limit(3)

    if (newsError) throw newsError

    const response = {
      news: newsData || []
    }

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: corsHeaders
    })
  } catch (error) {
    console.error('Error fetching member data:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: corsHeaders
    })
  }
}