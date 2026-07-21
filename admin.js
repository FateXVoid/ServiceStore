const cfg=window.APP_CONFIG||{};const sb=(cfg.supabaseUrl&&cfg.supabaseAnonKey)?supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey):null;let state={};
const $=s=>document.querySelector(s),money=n=>`฿${Number(n||0).toLocaleString()}`;function toast(t){const x=$('#toast');x.textContent=t;x.classList.add('show');setTimeout(()=>x.classList.remove('show'),2300)}
async function api(action, payload = {}) {
  if (!sb) throw new Error("ยังไม่ได้ตั้งค่า app-config.js");

  const {
    data: { session },
    error: sessionError
  } = await sb.auth.getSession();

  if (sessionError) throw new Error(sessionError.message);
  if (!session?.access_token) {
    throw new Error("กรุณาเข้าสู่ระบบจากหน้าร้านก่อน");
  }

  const response = await fetch(
    `${cfg.supabaseUrl}/functions/v1/admin-api`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": cfg.supabaseAnonKey,
        "Authorization": `Bearer ${session.access_token}`
      },
      body: JSON.stringify({ action, ...payload })
    }
  );

  const text = await response.text();
  let result = {};

  try {
    result = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`API ตอบข้อมูลผิดรูปแบบ (${response.status})`);
  }

  if (!response.ok) {
    throw new Error(result.detail || result.error || `API Error ${response.status}`);
  }

  return result;
}

const responseText = await response.text();

let result = {};

try {
  result = responseText ? JSON.parse(responseText) : {};
} catch {
  throw new Error(
    `admin-api ตอบข้อมูลผิดรูปแบบ (${response.status}): ${responseText.slice(0, 150)}`
  );
}

if (!response.ok) {
  throw new Error(
    result.detail ||
    result.error ||
    `admin-api error ${response.status}`
  );
}

return result;

  if (error) {
    console.error("admin-api invoke error:", error);

    let message = error.message || "เรียก admin-api ไม่สำเร็จ";

    try {
      if (error.context && typeof error.context.json === "function") {
        const responseBody = await error.context.json();
        message =
          responseBody?.detail ||
          responseBody?.error ||
          message;
      }
    } catch (readError) {
      console.error("อ่าน error response ไม่สำเร็จ:", readError);
    }

    throw new Error(message);
  }

  if (data?.error) {
    throw new Error(data.detail || data.error);
  }

  return data;
