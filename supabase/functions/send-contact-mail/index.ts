import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
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
    const to = Deno.env.get("RESEND_TO_EMAIL");

    if (!resendApiKey || !from || !to) {
      return new Response("Missing environment variables", {
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
