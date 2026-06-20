import { Resend } from "npm:resend@3.0.0";

interface SendStaffLoginMailRequest {
  staff_email: string;
  staff_name: string;
  company_name: string;
  login_id: string;
  password: string;
  login_url: string;
}

const resend = new Resend(Deno.env.get("RESEND_API_KEY"));
const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") || "";

Deno.serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response("OK", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ ok: false, error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body: SendStaffLoginMailRequest = await req.json();

    const { staff_email, staff_name, company_name, login_id, password, login_url } = body;

    // Validation
    if (!staff_email || !login_id || !password || !staff_name) {
      return new Response(JSON.stringify({ ok: false, error: "Missing required fields" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Email template
    const htmlContent = `
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CIDMログイン情報</title>
  <style>
    body { font-family: 'Segoe UI', 'Arial', sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; background: #f9f9f9; }
    .header { background: linear-gradient(135deg, #2563eb, #0ea5e9); color: white; padding: 20px; border-radius: 8px 8px 0 0; text-align: center; }
    .content { background: white; padding: 20px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .company { font-size: 18px; font-weight: bold; margin: 15px 0; color: #1e293b; }
    .staff-name { font-size: 16px; color: #64748b; margin-bottom: 20px; }
    .section { margin: 20px 0; padding: 15px; background: #f0f7ff; border-left: 4px solid #2563eb; border-radius: 4px; }
    .section-label { font-weight: bold; color: #2563eb; margin-bottom: 10px; }
    .login-box { background: #fff3cd; padding: 15px; border-radius: 6px; margin: 10px 0; font-family: 'Courier New', monospace; }
    .label { font-weight: 600; color: #64748b; margin-top: 10px; }
    .value { padding: 8px 12px; background: #f1f5f9; border-radius: 4px; margin: 5px 0; word-break: break-all; }
    .button { display: inline-block; padding: 12px 24px; background: linear-gradient(135deg, #2563eb, #0ea5e9); color: white; text-decoration: none; border-radius: 6px; margin: 20px 0; }
    .footer { text-align: center; font-size: 12px; color: #94a3b8; margin-top: 30px; padding-top: 20px; border-top: 1px solid #e2e8f0; }
    .warning { background: #fee2e2; border-left: 4px solid #dc2626; padding: 12px; border-radius: 4px; margin: 15px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔐 CIDM ログイン情報</h1>
      <p>担当者アカウント作成のお知らせ</p>
    </div>
    
    <div class="content">
      <p>${staff_name} 様</p>
      <p>いつもお世話になっています。</p>
      
      <div class="company">
        ${company_name}
      </div>
      
      <p>お手数ですが、下記のログイン情報にて、<strong>CIDM（会員情報管理システム）</strong>にアクセスしていただけますようお願いいたします。</p>
      
      <div class="section">
        <div class="section-label">📧 ログイン情報</div>
        <div class="label">ログインID（メールアドレス）</div>
        <div class="value">${login_id}</div>
        <div class="label">パスワード</div>
        <div class="value">${password}</div>
      </div>
      
      <div class="warning">
        <strong>⚠️ 注意事項</strong>
        <ul>
          <li>初回ログイン後、パスワードの変更をお願いいたします</li>
          <li>パスワードは他のユーザーと共有しないでください</li>
          <li>このメールは大切に保管してください</li>
        </ul>
      </div>
      
      <a href="${login_url}" class="button">CIDM にアクセス</a>
      
      <p style="margin-top: 30px;">ご不明な点やアクセスに関するお問い合わせは、お気軽にお知らせください。</p>
      <p>よろしくお願いいたします。</p>
    </div>
    
    <div class="footer">
      <p>このメールは自動送信です。返信はできませんのでご注意ください。</p>
      <p>© 2026 CIDM. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
    `;

    const textContent = `
CIDM ログイン情報

${staff_name} 様

いつもお世話になっています。

会社: ${company_name}

お手数ですが、下記のログイン情報にてCIDM（会員情報管理システム）にアクセスしていただけますようお願いいたします。

【ログイン情報】
ログインID（メールアドレス）: ${login_id}
パスワード: ${password}

【注意事項】
- 初回ログイン後、パスワードの変更をお願いいたします
- パスワードは他のユーザーと共有しないでください
- このメールは大切に保管してください

ログインURL: ${login_url}

ご不明な点やアクセスに関するお問い合わせは、お気軽にお知らせください。

よろしくお願いいたします。

---
このメールは自動送信です。返信はできませんのでご注意ください。
© 2026 CIDM. All rights reserved.
    `;

    // Send email via Resend
    const { data, error } = await resend.emails.send({
      from: resendFromEmail,
      to: staff_email,
      subject: `【CIDM】ログイン情報のお知らせ - ${company_name}`,
      html: htmlContent,
      text: textContent,
    });

    if (error) {
      console.error("Resend error:", error);
      return new Response(JSON.stringify({ ok: false, error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log("Email sent successfully:", data);

    return new Response(JSON.stringify({ ok: true, message_id: data?.id }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(JSON.stringify({ ok: false, error: error instanceof Error ? error.message : "Unknown error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
