import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

interface NewsItem {
  event_date: string
  category: string
  title: string
  details?: string
  detail_text?: string
}

interface DocumentItem {
  title: string
  file_url: string
  file_type: string
  file_size: string
  updated_at: string
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  try {
    // Load news
    const { data: newsData, error: newsError } = await supabase
      .from('meeting_reports')
      .select('event_date, category, title, details, detail_text')
      .eq('is_visible', true)
      .order('event_date', { ascending: false })
      .limit(3)

    if (newsError) throw newsError

    // Load documents
    const { data: docData, error: docError } = await supabase
      .from('member_documents')
      .select('title, file_url, file_type, file_size, updated_at')
      .order('updated_at', { ascending: false })
      .limit(4)

    if (docError) throw docError

    const response = {
      news: newsData || [],
      documents: docData || []
    }

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET',
        'Access-Control-Allow-Headers': 'Content-Type'
      }
    })
  } catch (error) {
    console.error('Error fetching member data:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
}