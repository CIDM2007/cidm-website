import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

// Add any additional trusted origins (e.g. a local dev server) here.
const ALLOWED_ORIGINS = new Set([
  "https://www.cidm.or.jp",
  "https://cidm.or.jp",
]);

function getCorsHeaders(origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin) ? origin : "https://www.cidm.or.jp",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function getClientIp(req: Request): string {
  const forwardedFor = req.headers.get("x-forwarded-for") || "";
  const first = forwardedFor.split(",")[0]?.trim();
  return first || req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "unknown";
}

async function checkRateLimit(
  supabaseUrl: string,
  apiKey: string,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
  try {
    const res = await fetch(`${supabaseUrl}/rest/v1/rpc/cidm_check_rate_limit`, {
      method: "POST",
      headers: {
        apikey: apiKey,
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_key: key, p_limit: limit, p_window_seconds: windowSeconds }),
    });
    if (!res.ok) return true;
    const withinLimit = await res.json();
    return withinLimit !== false;
  } catch (_error) {
    return true;
  }
}

serve(async (req) => {
  const origin = req.headers.get("origin") || "";
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: corsHeaders,
    });
  }

  try {
    const payload = await req.json();
    const {
      company,
      department,
      name,
      postal,
      pref,
      address,
      phone,
      fax,
      email,
      category,
      message,
      hp_field,
    } = payload;

    // Honeypot: a hidden field real users never fill in. Pretend success
    // so bots don't adapt, but never store or forward the submission.
    if (String(hp_field || "").trim()) {
      return new Response(
        JSON.stringify({ ok: true, inquiry_id: null, sent_to: null, mode: "stored_only" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!name || !postal || !pref || !address || !phone || !email || !message) {
      return new Response("Missing required fields", {
        status: 400,
        headers: corsHeaders,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = String(
      Deno.env.get("CIDM_SUPABASE_SECRET_KEY") ||
      Deno.env.get("SUPABASE_SECRET_KEY") ||
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
      "",
    ).trim();

    if (supabaseUrl && supabaseServiceRoleKey) {
      const clientIp = getClientIp(req);
      const withinLimit = await checkRateLimit(
        supabaseUrl,
        supabaseServiceRoleKey,
        `send_contact_mail:${clientIp}`,
        5,
        3600,
      );
      if (!withinLimit) {
        return new Response(
          JSON.stringify({ error: "リクエストが多すぎます。しばらく時間をおいて再度お試しください。" }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    let to = "carinformationdatamanagement@gmail.com";
    let inquiryId: string | null = null;

    if (supabaseUrl && supabaseServiceRoleKey) {
      try {
        const settingRes = await fetch(
          `${supabaseUrl}/rest/v1/app_settings?setting_key=eq.contact_to_email&select=setting_value&limit=1`,
          {
            method: "GET",
            headers: {
              apikey: supabaseServiceRoleKey,
            },
          },
        );

        if (settingRes.ok) {
          const settingData = await settingRes.json();
          if (Array.isArray(settingData) && settingData[0]?.setting_value) {
            to = String(settingData[0].setting_value);
          }
        }
      } catch (_error) {
        // Best effort only: fall back to the default recipient label.
      }

      try {
        const inquiryRes = await fetch(`${supabaseUrl}/rest/v1/contact_inquiries`, {
          method: "POST",
          headers: {
            apikey: supabaseServiceRoleKey,
            "Content-Type": "application/json",
            Prefer: "return=representation",
          },
          body: JSON.stringify({
            company,
            department,
            name,
            postal,
            pref,
            address,
            phone,
            fax,
            email,
            category,
            message,
            sent_to: to || null,
            send_status: "sent",
            sent_at: new Date().toISOString(),
            send_error: null,
          }),
        });

        if (inquiryRes.ok) {
          const inquiryData = await inquiryRes.json();
          if (Array.isArray(inquiryData) && inquiryData[0]?.id) {
            inquiryId = String(inquiryData[0].id);
          }
        }
      } catch (_error) {
        // Best effort only: even if storage fails, keep the public response consistent.
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        inquiry_id: inquiryId,
        sent_to: to,
        mode: "stored_only",
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  } catch (error) {
    return new Response(String(error), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
