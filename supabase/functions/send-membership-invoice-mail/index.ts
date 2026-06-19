import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function getCorsHeaders(_origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
    "Access-Control-Max-Age": "86400",
  };
}

type BillingRecipient = {
  member_id: string;
  email: string;
  staff_name?: string;
  company_name?: string;
  member_type?: string;
  amount: number;
};

type Payload = {
  billing_year?: number;
  billing_month?: number;
  due_date?: string;
  mail_body?: string;
  invoice_base_url?: string;
  recipients?: BillingRecipient[];
};

const DEFAULT_MAIL_BODY = [
  "平素より一般社団法人車両情報活用研究所の活動にご理解ご協力を賜り、誠にありがとうございます。",
  "下記の通り会費をご請求申し上げます。",
  "請求書は以下のURLよりご確認いただき、印刷してご利用ください。",
].join("\n");

function buildInvoiceNo(year: number, month: number, seq: number): string {
  const yy = String(year).slice(-2);
  const mm = String(month).padStart(2, "0");
  const n = String(seq).padStart(3, "0");
  return `CIDM-${yy}${mm}-${n}`;
}

serve(async (req) => {
  const origin = req.headers.get("origin") || "";
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: corsHeaders,
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("CIDM_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM_EMAIL");

    if (!supabaseUrl || !serviceRoleKey || !resendApiKey || !from) {
      return new Response("Missing environment variables", {
        status: 500,
        headers: corsHeaders,
      });
    }

    const payload = (await req.json()) as Payload;
    const billingYear = Number(payload.billing_year);
    const billingMonth = Number(payload.billing_month);
    const dueDate = String(payload.due_date || "").trim();
    const recipients = Array.isArray(payload.recipients) ? payload.recipients : [];
    const mailBody = String(payload.mail_body || "").trim() || DEFAULT_MAIL_BODY;
    const invoiceBaseUrl = String(payload.invoice_base_url || "").trim();

    if (
      !Number.isInteger(billingYear) ||
      billingYear < 2000 ||
      billingYear > 2100 ||
      !Number.isInteger(billingMonth) ||
      billingMonth < 1 ||
      billingMonth > 12 ||
      !dueDate ||
      !invoiceBaseUrl ||
      recipients.length === 0
    ) {
      return new Response("Missing required fields", {
        status: 400,
        headers: corsHeaders,
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    let successCount = 0;
    let failedCount = 0;
    const failures: Array<{ email: string; message: string }> = [];
    const results: Array<{ email: string; success: boolean; invoiceUrl?: string; invoiceNo?: string; message?: string }> = [];

    const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

    for (let i = 0; i < recipients.length; i += 1) {
      const r = recipients[i];
      const email = String(r?.email || "").trim();
      const memberId = String(r?.member_id || "").trim();
      const amount = Number(r?.amount || 0);

      if (!email || !memberId || !Number.isFinite(amount) || amount <= 0) {
        failedCount += 1;
        const msg = "email, member_id or amount is invalid";
        failures.push({ email: email || "(missing)", message: msg });
        results.push({ email: email || "(missing)", success: false, message: msg });
        continue;
      }

      const invoiceNo = buildInvoiceNo(billingYear, billingMonth, i + 1);

      const { data: issueRow, error: issueInsertError } = await supabase
        .from("membership_invoice_issues")
        .insert({
          member_id: memberId,
          billing_year: billingYear,
          billing_month: billingMonth,
          invoice_no: invoiceNo,
          amount,
          due_date: dueDate,
          company_name_snapshot: r.company_name || null,
          staff_name_snapshot: r.staff_name || null,
          staff_email_snapshot: email,
          member_type_snapshot: r.member_type || null,
          mail_subject: `【CIDM】${billingYear}年度 会費請求のご案内`,
          mail_body: mailBody,
          send_status: "failed",
          sent_at: null,
        })
        .select("id, access_token")
        .single();

      if (issueInsertError || !issueRow) {
        failedCount += 1;
        const msg = issueInsertError?.message || "failed to create invoice issue";
        failures.push({ email, message: msg });
        results.push({ email, success: false, message: msg });
        await sleep(600);
        continue;
      }

      const invoiceUrl = `${invoiceBaseUrl}?token=${encodeURIComponent(String(issueRow.access_token))}`;
      const subject = `【CIDM】${billingYear}年度 会費請求のご案内`;

      const lines = [
        `${r.company_name || ""} ${r.staff_name || ""} 様`,
        "",
        mailBody,
        "",
        `請求年度: ${billingYear}年度`,
        `請求月: ${billingMonth}月`,
        `請求金額: 金 ${amount.toLocaleString("ja-JP")} 円`,
        `お支払期限: ${dueDate}`,
        "",
        "請求書URL:",
        invoiceUrl,
        "",
        "このURLはご本人専用です。",
      ];

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
          text: lines.join("\n"),
        }),
      });

      if (!resendResponse.ok) {
        failedCount += 1;
        const errorText = await resendResponse.text();
        const msg = errorText || "unknown error";
        await supabase
          .from("membership_invoice_issues")
          .update({
            send_status: "failed",
            error_message: msg,
            updated_at: new Date().toISOString(),
          })
          .eq("id", issueRow.id);

        failures.push({ email, message: msg });
        results.push({ email, success: false, invoiceUrl, invoiceNo, message: msg });
        await sleep(600);
        continue;
      }

      successCount += 1;
      await supabase
        .from("membership_invoice_issues")
        .update({
          send_status: "success",
          error_message: null,
          sent_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", issueRow.id);

      results.push({ email, success: true, invoiceUrl, invoiceNo });
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
