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
    } = payload;

    if (!name || !postal || !pref || !address || !phone || !email || !message) {
      return new Response("Missing required fields", {
        status: 400,
        headers: corsHeaders,
      });
    }

    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM_EMAIL");
    const toFromEnv = Deno.env.get("RESEND_TO_EMAIL");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!resendApiKey || !from) {
      return new Response("Missing environment variables", {
        status: 500,
        headers: corsHeaders,
      });
    }

    let to = toFromEnv || "";
    let inquiryId: string | null = null;

    if (supabaseUrl && supabaseServiceRoleKey) {
        const settingRes = await fetch(
          `${supabaseUrl}/rest/v1/app_settings?setting_key=eq.contact_to_email&select=setting_value&limit=1`,
          {
            method: "GET",
            headers: {
              apikey: supabaseServiceRoleKey,
              Authorization: `Bearer ${supabaseServiceRoleKey}`,
            },
          },
        );

        if (settingRes.ok) {
          const settingData = await settingRes.json();
          if (Array.isArray(settingData) && settingData[0]?.setting_value) {
            to = String(settingData[0].setting_value);
          }
        }

        const inquiryRes = await fetch(`${supabaseUrl}/rest/v1/contact_inquiries`, {
          method: "POST",
          headers: {
            apikey: supabaseServiceRoleKey,
            Authorization: `Bearer ${supabaseServiceRoleKey}`,
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
            send_status: "pending",
          }),
        });

        if (inquiryRes.ok) {
          const inquiryData = await inquiryRes.json();
          if (Array.isArray(inquiryData) && inquiryData[0]?.id) {
            inquiryId = String(inquiryData[0].id);
          }
        }
    }

    if (!to) {
      return new Response("Missing contact recipient email", {
        status: 500,
        headers: corsHeaders,
      });
    }

    const subject = "新しいお問い合わせが届きました";
    const text = [
      `会社名: ${company ?? ""}`,
      `部署名: ${department ?? ""}`,
      `氏名: ${name ?? ""}`,
      `郵便番号: ${postal ?? ""}`,
      `都道府県: ${pref ?? ""}`,
      `住所: ${address ?? ""}`,
      `電話番号: ${phone ?? ""}`,
      `FAX番号: ${fax ?? ""}`,
      `Eメール: ${email ?? ""}`,
      `分類: ${category ?? ""}`,
      "",
      "--- お問い合わせ内容 ---",
      String(message ?? ""),
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

      if (inquiryId && supabaseUrl && supabaseServiceRoleKey) {
        await fetch(`${supabaseUrl}/rest/v1/contact_inquiries?id=eq.${inquiryId}`, {
          method: "PATCH",
          headers: {
            apikey: supabaseServiceRoleKey,
            Authorization: `Bearer ${supabaseServiceRoleKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ send_status: "failed", send_error: errorText || "unknown error" }),
        });
      }

      return new Response(errorText, {
        status: 500,
        headers: corsHeaders,
      });
    }

    if (inquiryId && supabaseUrl && supabaseServiceRoleKey) {
      await fetch(`${supabaseUrl}/rest/v1/contact_inquiries?id=eq.${inquiryId}`, {
        method: "PATCH",
        headers: {
          apikey: supabaseServiceRoleKey,
          Authorization: `Bearer ${supabaseServiceRoleKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ send_status: "sent", sent_at: new Date().toISOString(), send_error: null }),
      });
    }

    return new Response(JSON.stringify({ ok: true, inquiry_id: inquiryId, sent_to: to }), {
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
