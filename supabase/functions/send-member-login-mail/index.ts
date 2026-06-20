import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

function getCorsHeaders(_origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
    "Access-Control-Max-Age": "86400",
  };
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
    const email = String(payload?.email || payload?.login_id || "").trim();
    const loginId = String(payload?.login_id || email || "").trim();
    const password = String(payload?.password || payload?.initial_password || "").trim();
    const memberName = String(payload?.member_name || payload?.staff_name || "").trim();
    const companyName = String(payload?.company_name || payload?.org_name || "").trim();
    const loginUrl = String(payload?.login_url || "").trim() || "https://cidm2007.github.io/cidm-website/";

    const resendApiKey = String(Deno.env.get("RESEND_API_KEY") || "").trim();
    const from = String(Deno.env.get("RESEND_FROM_EMAIL") || "").trim();

    if (!email || !loginId || !password) {
      return new Response("Missing required fields", {
        status: 400,
        headers: corsHeaders,
      });
    }

    if (!resendApiKey || !from) {
      return new Response("Missing environment variables", {
        status: 500,
        headers: corsHeaders,
      });
    }

    const subject = "【CIDM】会員サイトの初期ログイン情報のご案内";
    const text = [
      `${companyName || "CIDM会員"}${memberName ? ` ${memberName}` : ""} 様`,
      "",
      "CIDM会員サイトの初期ログイン情報をご案内いたします。",
      "下記URLよりログインをお願いいたします。",
      "",
      `ログインID: ${loginId}`,
      `初期パスワード: ${password}`,
      "",
      "ログインURL: ",
      loginUrl,
      "",
      "初回ログイン後は、パスワードの変更をお願いいたします。",
      "このメールにお心当たりがない場合は、お手数ですが破棄してください。",
    ].join("\n");

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [email],
        subject,
        text,
      }),
    });

    if (!resendResponse.ok) {
      const errorText = await resendResponse.text();
      return new Response(errorText, {
        status: 500,
        headers: corsHeaders,
      });
    }

    return new Response(JSON.stringify({ ok: true, sent_to: email }), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  } catch (error) {
    return new Response(String(error), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
