import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!url || !anonKey || !serviceKey) {
      return json({ error: "missing_supabase_environment_variables" }, 500);
    }

    const authorization = req.headers.get("Authorization") || "";
    const token = authorization.replace(/^Bearer\s+/i, "").trim();

    if (!token) {
      return json({ error: "missing_access_token" }, 401);
    }

    const authClient = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } =
      await authClient.auth.getUser(token);

    if (userError || !userData.user) {
      return json(
        { error: "invalid_session", detail: userError?.message || "User not found" },
        401,
      );
    }

    const user = userData.user;
    const db = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: role, error: roleError } = await db
      .from("admin_users")
      .select("user_id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (roleError) {
      return json({ error: "admin_lookup_failed", detail: roleError.message }, 500);
    }

    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid_json_body" }, 400);
    }

    const action = String(body.action || "");

    if (action === "me") {
      return json({
        version: "admin-api-v2",
        is_admin: Boolean(role),
        email: user.email || "",
        user_id: user.id,
      });
    }

    if (!role) {
      return json({ error: "forbidden" }, 403);
    }

    if (action === "approve_topup") {
      const { data, error } = await db.rpc("admin_approve_topup", {
        p_request_id: body.request_id,
        p_admin_id: user.id,
        p_note: String(body.note || ""),
      });
      if (error) throw error;
      return json({ ok: true, new_balance: data });
    }

    if (action === "reject_topup") {
      const { data, error } = await db
        .from("topup_requests")
        .update({
          status: "rejected",
          admin_note: String(body.note || ""),
          reviewed_by: user.id,
          reviewed_at: new Date().toISOString(),
        })
        .eq("id", body.request_id)
        .eq("status", "pending")
        .select("id")
        .maybeSingle();

      if (error) throw error;
      return data ? json({ ok: true }) : json({ error: "already_reviewed" }, 409);
    }

    if (action === "adjust_credit") {
      const { data, error } = await db.rpc("admin_adjust_credit", {
        p_user_id: body.user_id,
        p_amount: Number(body.amount),
        p_admin_id: user.id,
        p_note: String(body.note || ""),
      });
      if (error) throw error;
      return json({ ok: true, new_balance: data });
    }

    if (action === "add_ledger") {
      const { error } = await db.from("admin_ledger").insert({
        amount: Number(body.amount),
        note: String(body.note || ""),
        created_by: user.id,
      });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action !== "dashboard") {
      return json({ error: "unknown_action" }, 400);
    }

    const [topupResult, profileResult, ledgerResult, authUsersResult] =
      await Promise.all([
        db.from("topup_requests").select("*").order("created_at", { ascending: false }).limit(200),
        db.from("profiles").select("id,email,credit_balance,created_at").order("created_at", { ascending: false }).limit(500),
        db.from("admin_ledger").select("*").order("created_at", { ascending: false }).limit(300),
        db.auth.admin.listUsers({ page: 1, perPage: 1000 }),
      ]);

    const firstError =
      topupResult.error ||
      profileResult.error ||
      ledgerResult.error ||
      authUsersResult.error;

    if (firstError) throw firstError;

    const emailById = new Map(
      (authUsersResult.data.users || []).map((item) => [item.id, item.email]),
    );

    const topups = [];
    for (const item of topupResult.data || []) {
      let slipUrl = "";
      if (item.slip_path) {
        const { data: signed } = await db.storage
          .from("payment-slips")
          .createSignedUrl(item.slip_path, 900);
        slipUrl = signed?.signedUrl || "";
      }

      topups.push({
        ...item,
        email: emailById.get(item.user_id) || null,
        slip_url: slipUrl,
      });
    }

    const users = (profileResult.data || []).map((item) => ({
      ...item,
      email: item.email || emailById.get(item.id) || null,
    }));

    const approved = (topupResult.data || []).filter(
      (item) => item.status === "approved",
    );

    const daily_income = [];
    for (let i = 13; i >= 0; i--) {
      const date = new Date();
      date.setHours(0, 0, 0, 0);
      date.setDate(date.getDate() - i);
      const key = date.toISOString().slice(0, 10);

      daily_income.push({
        day: key.slice(5),
        total: approved
          .filter((item) => item.reviewed_at?.slice(0, 10) === key)
          .reduce((sum, item) => sum + Number(item.amount || 0), 0),
      });
    }

    return json({
      version: "admin-api-v2",
      stats: {
        approved_income: approved.reduce(
          (sum, item) => sum + Number(item.amount || 0),
          0,
        ),
        total_credit_balance: (profileResult.data || []).reduce(
          (sum, item) => sum + Number(item.credit_balance || 0),
          0,
        ),
        pending_topups: (topupResult.data || []).filter(
          (item) => item.status === "pending",
        ).length,
        users: (authUsersResult.data.users || []).length,
      },
      daily_income,
      topups,
      users,
      ledger: ledgerResult.data || [],
    });
  } catch (error) {
    console.error("admin-api error:", error);
    return json(
      {
        error: "internal_server_error",
        detail: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});
