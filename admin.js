const cfg = window.APP_CONFIG || {};
const sb = cfg.supabaseUrl && cfg.supabaseAnonKey
  ? supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey)
  : null;

let state = {};
const $ = (selector) => document.querySelector(selector);
const money = (value) => `฿${Number(value || 0).toLocaleString("th-TH")}`;

function toast(message) {
  const element = $("#toast");
  if (!element) return;
  element.textContent = message;
  element.classList.add("show");
  setTimeout(() => element.classList.remove("show"), 2600);
}

async function api(action, payload = {}) {
  if (!sb) throw new Error("ยังไม่ได้ตั้งค่า app-config.js");

  const { data, error: sessionError } = await sb.auth.getSession();
  if (sessionError) throw new Error(sessionError.message);

  const token = data.session?.access_token;
  if (!token) throw new Error("กรุณาเข้าสู่ระบบจากหน้าร้านก่อน");

  let response;
  try {
    response = await fetch(`${cfg.supabaseUrl}/functions/v1/admin-api`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: cfg.supabaseAnonKey,
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ action, ...payload }),
    });
  } catch (error) {
    console.error("admin-api network error:", error);
    throw new Error("เชื่อมต่อระบบหลังบ้านไม่ได้ กรุณาลองใหม่");
  }

  const text = await response.text();
  let result = {};
  try {
    result = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`ระบบหลังบ้านตอบข้อมูลผิดรูปแบบ (${response.status})`);
  }

  if (!response.ok) {
    throw new Error(result.detail || result.error || `API Error ${response.status}`);
  }

  return result;
}

async function boot() {
  try {
    if (!sb) throw new Error("ยังไม่ได้ตั้งค่า app-config.js");

    const me = await api("me");
    if (!me.is_admin) throw new Error("บัญชีนี้ไม่มีสิทธิ์เข้าหน้าหลังบ้าน");

    $("#adminIdentity").textContent = `Owner • ${me.email || "Admin"}`;
    $("#gate").classList.add("hidden");
    $("#app").classList.remove("hidden");
    await load();
  } catch (error) {
    console.error("Admin boot failed:", error);
    $("#gateText").textContent = error.message || "เปิดหน้าหลังบ้านไม่สำเร็จ";
    $("#backBtn").classList.remove("hidden");
  }
}

async function load() {
  try {
    state = await api("dashboard");
    render();
  } catch (error) {
    console.error("Dashboard load failed:", error);
    toast(error.message);
  }
}

function render() {
  const stats = state.stats || {};
  $("#statIncome").textContent = money(stats.approved_income);
  $("#statCredits").textContent = money(stats.total_credit_balance);
  $("#statPending").textContent = stats.pending_topups || 0;
  $("#statUsers").textContent = stats.users || 0;
  $("#pendingChip").textContent = `${stats.pending_topups || 0} pending`;
  renderChart();
  renderRecent();
  renderTopups();
  renderUsers();
  renderLedger();
}

function renderChart() {
  const data = state.daily_income || [];
  const max = Math.max(1, ...data.map((item) => Number(item.total || 0)));
  $("#incomeChart").innerHTML = data.map((item) => {
    const height = Math.max(5, (Number(item.total || 0) / max) * 100);
    return `<div class="bar" style="--h:${height}%" data-label="${item.day}: ${money(item.total)}"></div>`;
  }).join("") || '<p style="color:var(--muted)">ยังไม่มีข้อมูล</p>';
}

function renderRecent() {
  const items = (state.topups || []).slice(0, 6);
  $("#recentList").innerHTML = items.map((item) => `
    <div style="display:flex;justify-content:space-between;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)">
      <div><b>${item.email || "ผู้ใช้"}</b><small style="display:block;color:var(--muted)">${new Date(item.created_at).toLocaleString("th-TH")}</small></div>
      <div style="text-align:right"><b>${money(item.amount)}</b><small class="status ${item.status}" style="display:block">${item.status}</small></div>
    </div>`).join("") || '<p style="color:var(--muted)">ยังไม่มีรายการ</p>';
}

function renderTopups() {
  const items = state.topups || [];
  $("#topupRows").innerHTML = items.map((item) => {
    const safeId = String(item.user_id || "").slice(0, 8);
    const slip = item.slip_url
      ? `<img class="thumb" src="${item.slip_url}" alt="สลิป" onclick='openSlip(${JSON.stringify(item)})'>`
      : "-";
    const actions = item.status === "pending"
      ? `<button class="btn good" onclick="review('${item.id}','approve')">อนุมัติ</button> <button class="btn bad" onclick="review('${item.id}','reject')">ปฏิเสธ</button>`
      : "-";
    return `<tr><td>${slip}</td><td>${item.email || "-"}<small>${safeId}</small></td><td><b>${money(item.amount)}</b></td><td>${item.transfer_reference || "-"}</td><td>${new Date(item.created_at).toLocaleString("th-TH")}</td><td><span class="status ${item.status}">${item.status}</span></td><td>${actions}</td></tr>`;
  }).join("") || '<tr><td colspan="7">ไม่มีรายการ</td></tr>';
}

function renderUsers() {
  const items = state.users || [];
  $("#userRows").innerHTML = items.map((item) => `
    <tr><td>${item.email || "-"}<small>${item.id}</small></td><td><b>${money(item.credit_balance)}</b></td><td>${new Date(item.created_at).toLocaleDateString("th-TH")}</td><td><button class="btn" onclick="selectUser('${item.id}')">เลือก</button></td></tr>`
  ).join("") || '<tr><td colspan="4">ไม่มีผู้ใช้</td></tr>';
}

function renderLedger() {
  const items = state.ledger || [];
  $("#ledgerRows").innerHTML = items.map((item) => `
    <tr><td><span class="status ${item.amount >= 0 ? "approved" : "rejected"}">${item.amount >= 0 ? "รายรับ" : "รายจ่าย"}</span></td><td><b>${item.amount >= 0 ? "+" : ""}${money(item.amount)}</b></td><td>${item.note || "-"}</td><td>${new Date(item.created_at).toLocaleString("th-TH")}</td></tr>`
  ).join("") || '<tr><td colspan="4">ไม่มีรายการ</td></tr>';
}

async function review(id, mode) {
  const note = prompt(mode === "approve" ? "หมายเหตุการอนุมัติ (ไม่บังคับ)" : "เหตุผลที่ปฏิเสธ") || "";
  try {
    await api(mode === "approve" ? "approve_topup" : "reject_topup", { request_id: id, note });
    toast(mode === "approve" ? "เพิ่มเครดิตแล้ว" : "ปฏิเสธรายการแล้ว");
    await load();
  } catch (error) {
    toast(error.message);
  }
}

function selectUser(id) {
  $("#adjustUserId").value = id;
  document.querySelector('[data-section="users"]')?.click();
}

async function adjust() {
  try {
    await api("adjust_credit", {
      user_id: $("#adjustUserId").value.trim(),
      amount: Number($("#adjustAmount").value),
      note: $("#adjustNote").value.trim(),
    });
    toast("ปรับเครดิตเรียบร้อย");
    $("#adjustAmount").value = "";
    $("#adjustNote").value = "";
    await load();
  } catch (error) {
    toast(error.message);
  }
}

async function addLedger() {
  try {
    await api("add_ledger", {
      amount: Number($("#ledgerAmount").value),
      note: $("#ledgerNote").value.trim(),
    });
    toast("เพิ่มรายการบัญชีแล้ว");
    $("#ledgerAmount").value = "";
    $("#ledgerNote").value = "";
    await load();
  } catch (error) {
    toast(error.message);
  }
}

window.openSlip = (item) => {
  $("#modalSlip").src = item.slip_url;
  $("#modalInfo").textContent = `${item.email || "ผู้ใช้"} • ${money(item.amount)} • ${item.transfer_reference || ""}`;
  $("#slipModal").classList.add("open");
};
window.closeSlip = () => $("#slipModal").classList.remove("open");
window.review = review;
window.selectUser = selectUser;

document.querySelectorAll("[data-section]").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll("[data-section]").forEach((item) => item.classList.toggle("active", item === button));
    document.querySelectorAll(".section").forEach((section) => section.classList.toggle("active", section.id === button.dataset.section));
    $("#pageTitle").textContent = button.textContent.trim();
  });
});

$("#refreshBtn")?.addEventListener("click", load);
$("#adjustBtn")?.addEventListener("click", adjust);
$("#ledgerBtn")?.addEventListener("click", addLedger);
$("#logoutBtn")?.addEventListener("click", async () => {
  await sb.auth.signOut();
  location.href = "index.html";
});

boot();
