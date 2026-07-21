const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

import { createClient } from "npm:@supabase/supabase-js@2";
const prices:Record<string,number> = { portfolio:499, delivery:99 };
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
Deno.serve(async(req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:corsHeaders});
  try{
    const authHeader=req.headers.get("Authorization")||"";
    const userClient=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:authHeader}}});
    const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const {data:{user},error}=await userClient.auth.getUser();
    if(error||!user) return json({error:"unauthorized"},401);
    const {service_id}=await req.json();
    const cost=prices[String(service_id)];
    if(!cost) return json({error:"invalid_service"},400);
    const {data,error:rpcError}=await admin.rpc("spend_service_credits",{p_user_id:user.id,p_service_id:String(service_id),p_cost:cost});
    if(rpcError) return json({error:rpcError.message},rpcError.message.includes("insufficient")?409:400);
    return json({ok:true,remaining_balance:data});
  }catch(error){return json({error:error instanceof Error?error.message:"internal_error"},500);}
});
