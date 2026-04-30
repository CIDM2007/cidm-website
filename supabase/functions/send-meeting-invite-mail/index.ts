import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

function getCorsHeaders(_origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
}

type Recipient = {
  email: string;
  staff_name?: string;
  company_name?: string;
  url?: string;
};

const DEFAULT_INVITE_MAIL_BODY = [
  "いつも、一般社団法人車両情報活用研究所へのご理解とご協力を賜り心からお礼申し上げます。",
  "さて下記のイベントについてご案内申し上げますので、出欠を下のURLからご回答くださいますようにお願いいたします。",
  "大変お忙しい中かとは存じますが、何卒ご出席を賜りますよう、宜しくお願い致します。",
].join("\n");

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
      event_name,
      event_description,
      starts_at,
      location_info,
      invite_mail_body,
      delivery_mode,
      recipients,
    } = payload as {
      event_name?: string;
      event_description?: string;
      starts_at?: string;
      location_info?: string;
      invite_mail_body?: string;
      delivery_mode?: string;
      recipients?: Recipient[];
    };

    if (!event_name || !starts_at || !Array.isArray(recipients) || recipients.length === 0) {
      return new Response("Missing required fields", {
        status: 400,
        headers: corsHeaders,
      });
    }

    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM_EMAIL");

    if (!resendApiKey || !from) {
      return new Response("Missing environment variables", {
        status: 500,
        headers: corsHeaders,
      });
    }

    const startsAtText = new Date(starts_at).toLocaleString("ja-JP", {
      timeZone: "Asia/Tokyo",
    });
    const subject = `【CIDM】${event_name} のご案内`;
    const mailBody = (invite_mail_body || "").trim() || DEFAULT_INVITE_MAIL_BODY;
    const mode = delivery_mode === "notice" ? "notice" : "rsvp";

    let successCount = 0;
    let failedCount = 0;
    const failures: Array<{ email: string; message: string }> = [];
    const results: Array<{ email: string; success: boolean; message?: string }> = [];

    const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

    for (const r of recipients) {
      const email = (r?.email || "").trim();
      const url = (r?.url || "").trim();
      if (!email || (mode === "rsvp" && !url)) {
        failedCount += 1;
        const msg = mode === "rsvp" ? "email or url is missing" : "email is missing";
        failures.push({ email: email || "(missing)", message: msg });
        results.push({ email: email || "(missing)", success: false, message: msg });
        continue;
      }

      const lines: string[] = [
        `${r.company_name || ""} ${r.staff_name || ""} 様`,
        "",
        mailBody,
        "",
        "",
        "",
        `イベント名: ${event_name}`,
        `開催日時: ${startsAtText}`,
        `開催場所/接続先: ${location_info || ""}`,
      ];

      if (event_description) {
        lines.push("", `内容: ${event_description}`);
      }

      if (mode === "rsvp") {
        lines.push("", "回答URL:", url, "", "このURLはご本人専用です。");
      } else {
        if (event_description) {
          lines.push("", "");
        } else {
          lines.push("");
        }
        lines.push("本メールはご案内のみです。出欠のご回答は不要です。");
      }

      const text = lines.join("\n");

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
        failedCount += 1;
        const errorText = await resendResponse.text();
        failures.push({ email, message: errorText || "unknown error" });
        results.push({ email, success: false, message: errorText || "unknown error" });
        await sleep(600);
        continue;
      }

      successCount += 1;
      results.push({ email, success: true });

      // Resend rate limit: 2 req/sec → wait 600ms between sends
      await sleep(600);
    }

    return new Response(
      JSON.stringify({
        ok: failedCount === 0,
        successCount,
        failedCount,
        failures,
        results,
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
