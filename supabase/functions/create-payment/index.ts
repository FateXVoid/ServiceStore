const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status=200) => new Response(JSON.stringify(body), { status, headers:{...corsHeaders,"Content-Type":"application/json"} });
const basic = (key:string) => `Basic ${btoa(`${key}:`)}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers:corsHeaders });
  try {
    const authHeader = req.headers.get("Authorization") || "";
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global:{headers:{Authorization:authHeader}} });
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data:{user}, error:userError } = await supabase.auth.getUser();
    if (userError || !user) return json({error:"unauthorized"},401);

    const { amount, method, phone_number } = await req.json();
    const baht = Number(amount);
    if (!Number.isInteger(baht) || baht < 20 || baht > 5000) return json({error:"amount_must_be_20_to_5000"},400);
    if (!["promptpay","truemoney"].includes(method)) return json({error:"unsupported_method"},400);
    if (method === "truemoney" && !/^0\d{9}$/.test(String(phone_number||""))) return json({error:"invalid_phone_number"},400);

    const { data:payment, error:paymentError } = await admin.from("payments").insert({user_id:user.id,amount:baht,method}).select().single();
    if (paymentError) throw paymentError;

    const sourceParams = new URLSearchParams({ amount:String(baht*100), currency:"thb", type:method });
    if (method === "truemoney") sourceParams.set("phone_number", phone_number);
    const sourceRes = await fetch("https://api.omise.co/sources", { method:"POST", headers:{Authorization:basic(Deno.env.get("OMISE_PUBLIC_KEY")!),"Content-Type":"application/x-www-form-urlencoded"}, body:sourceParams });
    const source = await sourceRes.json();
    if (!sourceRes.ok || !source.id) {
      await admin.from("payments").update({status:"failed"}).eq("id",payment.id);
      return json({error:source.message || "source_creation_failed"},400);
    }

    const chargeParams = new URLSearchParams({ amount:String(baht*100), currency:"thb", source:source.id, description:`Credit top-up ${payment.id}` });
    const chargeRes = await fetch("https://api.omise.co/charges", { method:"POST", headers:{Authorization:basic(Deno.env.get("OMISE_SECRET_KEY")!),"Content-Type":"application/x-www-form-urlencoded"}, body:chargeParams });
    const charge = await chargeRes.json();
    if (!chargeRes.ok || !charge.id) {
      await admin.from("payments").update({status:"failed",gateway_source_id:source.id}).eq("id",payment.id);
      return json({error:charge.message || "charge_creation_failed"},400);
    }

    await admin.from("payments").update({gateway_source_id:source.id,gateway_charge_id:charge.id}).eq("id",payment.id);
    const qrImage = charge.source?.scannable_code?.image?.download_uri || source.scannable_code?.image?.download_uri || null;
    const authorizeUri = charge.authorize_uri || charge.source?.authorize_uri || source.authorize_uri || null;
    return json({payment_id:payment.id,charge_id:charge.id,qr_image:qrImage,authorize_uri:authorizeUri,status:charge.status});
  } catch (error) {
    console.error(error);
    return json({error:error instanceof Error ? error.message : "internal_error"},500);
  }
});
