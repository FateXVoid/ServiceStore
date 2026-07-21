const cfg=window.APP_CONFIG||{};const sb=(cfg.supabaseUrl&&cfg.supabaseAnonKey)?supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey):null;let state={};
const $=s=>document.querySelector(s),money=n=>`฿${Number(n||0).toLocaleString()}`;function toast(t){const x=$('#toast');x.textContent=t;x.classList.add('show');setTimeout(()=>x.classList.remove('show'),2300)}
async function api(action, payload = {}) {
  if (!sb) {
    throw new Error("ยังไม่ได้ตั้งค่า app-config.js");
  }

  const {
    data: { session },
    error: sessionError
  } = await sb.auth.getSession();

  if (sessionError) {
    throw new Error(sessionError.message);
  }

  if (!session?.access_token) {
    throw new Error("กรุณากลับหน้าร้านแล้วเข้าสู่ระบบใหม่");
  }

  const { data, error } = await sb.functions.invoke("admin-api", {
    body: {
      action,
      ...payload
    }
  });

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
}
