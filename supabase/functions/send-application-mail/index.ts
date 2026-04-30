import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

function getCorsHeaders(_origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
}

serve(async (req) => {
  const origin = req.headers.get("origin") || "";
  const corsHeaders = getCorsHeaders(origin);
  
  if (req.method === "OPTIONS") {
    return new Response("ok", { 
      status: 204,
      headers: corsHeaders 
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
      member_type,
      org_name,
      org_name_kana,
      zip_code,
      address,
      website,
      exec_name,
      staff_name,
      staff_title,
      staff_tel,
      staff_email,
    } = payload;

    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM_EMAIL");
    const to = Deno.env.get("RESEND_TO_EMAIL");

    if (!resendApiKey || !from || !to) {
      return new Response("Missing environment variables", {
        status: 500,
        headers: corsHeaders,
      });
    }

    const subject = "新しい入会申込が届きました";
    const text = [
      `会員種別: ${member_type ?? ""}`,
      `社名/団体名: ${org_name ?? ""}`,
      `社名/団体名かな: ${org_name_kana ?? ""}`,
      `郵便番号: ${zip_code ?? ""}`,
      `所在地: ${address ?? ""}`,
      `Webサイト: ${website ?? ""}`,
      `責任者名: ${exec_name ?? ""}`,
      `担当者名: ${staff_name ?? ""}`,
      `担当者役職: ${staff_title ?? ""}`,
      `担当者電話: ${staff_tel ?? ""}`,
      `担当者メール: ${staff_email ?? ""}`,
    ].join("\n");

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [to],
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

    return new Response(JSON.stringify({ ok: true }), {
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