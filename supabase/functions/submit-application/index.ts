import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  })
}

function firstFilled(source: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = source[key]
    if (typeof value === "string" && value.trim()) {
      return value.trim()
    }
  }
  return ""
}

function normalizeSecret(value: string | undefined | null): string {
  const raw = String(value ?? "").trim()
  if (!raw) return ""
  // Secret managers sometimes store quoted values; trim them for header safety.
  const unquoted =
    (raw.startsWith('"') && raw.endsWith('"')) || (raw.startsWith("'") && raw.endsWith("'"))
      ? raw.slice(1, -1)
      : raw
  return unquoted.replace(/[\r\n]+/g, "").trim()
}

function serializeError(input: unknown): { message: string; detail?: Record<string, unknown> } {
  if (input instanceof Error) {
    return { message: input.message || "Unknown error" }
  }

  if (typeof input === "string") {
    return { message: input }
  }

  if (input && typeof input === "object") {
    const asRecord = input as Record<string, unknown>
    const messageCandidate = [
      asRecord.message,
      asRecord.error_description,
      asRecord.details,
      asRecord.hint,
      asRecord.error,
      asRecord.code,
    ].find((value) => typeof value === "string" && value.trim())

    const detail: Record<string, unknown> = {}
    for (const key of ["code", "details", "hint", "message", "error"]) {
      if (asRecord[key] !== undefined) {
        detail[key] = asRecord[key]
      }
    }

    return {
      message: typeof messageCandidate === "string" ? messageCandidate : "Unexpected error",
      detail: Object.keys(detail).length > 0 ? detail : asRecord,
    }
  }

  return { message: String(input) }
}

async function notifyApplicationMail(
  supabaseUrl: string,
  serviceRoleKey: string,
  payload: Record<string, unknown>,
  registrationResult: Record<string, unknown>,
) {
  const response = await fetch(`${supabaseUrl}/functions/v1/send-application-mail`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      ...payload,
      application_status: registrationResult.application_status,
      member_id: registrationResult.member_id,
      registration_mode: registrationResult.mode,
    }),
  })

  if (!response.ok) {
    const responseText = await response.text()
    throw new Error(`send-application-mail failed: ${response.status} ${responseText}`)
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders,
    })
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405)
  }

  try {
    const supabaseUrl = normalizeSecret(Deno.env.get("SUPABASE_URL"))
    const serviceRoleKey = normalizeSecret(
      Deno.env.get("CIDM_SUPABASE_SECRET_KEY") ??
        Deno.env.get("SUPABASE_SECRET_KEY") ??
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
        "",
    )
    const rpcKey = normalizeSecret(
      Deno.env.get("SUPABASE_ANON_KEY") ??
        Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
        serviceRoleKey,
    )

    if (!supabaseUrl || !rpcKey) {
      throw new Error("Supabase credentials are not configured")
    }

    const payload = await request.json()
    const companyName = firstFilled(payload, ["company_name", "company", "companyName", "name"])
    const contactName = firstFilled(payload, ["contact_name", "staff_name", "applicant_name"])
    const contactEmail = firstFilled(payload, ["contact_email", "email", "staff_email", "applicant_email"])

    if (!companyName) {
      return jsonResponse({ error: "company_name is required" }, 400)
    }

    if (!contactName) {
      return jsonResponse({ error: "contact_name is required" }, 400)
    }

    if (!contactEmail) {
      return jsonResponse({ error: "contact_email is required" }, 400)
    }

    const supabase = createClient(supabaseUrl, rpcKey, {
      auth: { persistSession: false },
    })

    const { data, error } = await supabase.rpc("cidm_submit_application", {
      p_payload: payload,
    })

    if (error) {
      throw error
    }

    const registrationResult = (Array.isArray(data) ? data[0] : data) ?? {}
    let mailWarning: string | null = null

    try {
      if (!serviceRoleKey) {
        throw new Error("mail send skipped: service role key is not configured")
      }
      await notifyApplicationMail(supabaseUrl, serviceRoleKey, payload, registrationResult)
    } catch (mailError) {
      mailWarning = serializeError(mailError).message
      console.error(mailWarning)
    }

    return jsonResponse({
      ok: true,
      member_id: registrationResult.member_id ?? null,
      application_status: registrationResult.application_status ?? "未審査",
      mode: registrationResult.mode ?? "created",
      mail_warning: mailWarning,
    })
  } catch (error) {
    const serialized = serializeError(error)
    console.error(serialized)
    return jsonResponse({ error: serialized }, 500)
  }
})