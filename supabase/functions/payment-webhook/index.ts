const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

import { createClient } from "npm:@supabase/supabase-js@2";
const basic = (key:string) => `Basic ${btoa(`${key}:`)}`;

Deno.serve(async (req) => {
  try {
    const event = await req.json();
    if (event.key !== "charge.complete") return new Response("ignored",{status:200});
    const chargeId = event.data?.id;
    if (!chargeId) return new Response("missing_charge",{status:400});

    // Never trust the webhook body alone: retrieve the charge directly from Omise.
    const verifyRes = await fetch(`https://api.omise.co/charges/${encodeURIComponent(chargeId)}`, { headers:{Authorization:basic(Deno.env.get("OMISE_SECRET_KEY")!)} });
    const charge = await verifyRes.json();
    if (!verifyRes.ok) return new Response("verification_failed",{status:400});
    if (!(charge.paid === true && charge.status === "successful" && String(charge.currency).toLowerCase()==="thb")) return new Response("not_paid",{status:200});

    const admin = createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data:payment, error } = await admin.from("payments").select("id,amount,status,credited_at").eq("gateway_charge_id",chargeId).single();
    if (error || !payment) return new Response("payment_not_found",{status:404});
    if (Number(charge.amount) !== Number(payment.amount)*100) return new Response("amount_mismatch",{status:400});

    const { error:rpcError } = await admin.rpc("credit_paid_payment",{p_payment_id:payment.id,p_gateway_charge_id:chargeId});
    if (rpcError) { console.error(rpcError); return new Response("credit_failed",{status:500}); }
    return new Response("ok",{status:200});
  } catch (error) {
    console.error(error);
    return new Response("invalid_webhook",{status:400});
  }
});
