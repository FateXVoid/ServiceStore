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

function throwIfError(error, fallback) {
  if (error) throw new Error(error.message || fallback);
}

async function getAdminSession() {
  if (!sb) throw new Error("ยังไม่ได้ตั้งค่า app-config.js");

  const { data, error } = await sb.auth.getSession();
  throwIfError(error, "ตรวจสอบการเข้าสู่ระบบไม่สำเร็จ");
  if (!data.session?.user) throw new Error("กรุณาเข้าสู่ระบบจากหน้าร้านก่อน");

  const { data: isAdmin, error: adminError } = await sb.rpc("is_admin");
  throwIfError(adminError, "ตรวจสอบสิทธิ์แอดมินไม่สำเร็จ");
  if (!isAdmin) throw new Error("บัญชีนี้ไม่มีสิทธิ์เข้าหน้าหลังบ้าน");

  return data.session.user;
}

async function boot() {
  try {
    const user = await getAdminSession();
    $("#adminIdentity").textContent = `Owner • ${user.email || "Admin"}`;
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
    const [topupResult, profileResult, ledgerResult, withdrawalResult, orderResult, serviceResult] = await Promise.all([
      sb.from("topup_requests").select("*").order("created_at", { ascending: false }).limit(200),
      sb.rpc("admin_list_users"),
      sb.from("admin_ledger").select("*").order("created_at", { ascending: false }).limit(300),
      sb.from("withdrawal_requests").select("*").order("created_at", { ascending: false }).limit(200),
      sb.from("service_orders").select("*").order("created_at", { ascending: false }).limit(300),
      sb.from("services").select("*").order("sort_order", { ascending: true }),
    ]);

    throwIfError(topupResult.error, "โหลดรายการเติมเงินไม่สำเร็จ");
    throwIfError(profileResult.error, "โหลดข้อมูลลูกค้าไม่สำเร็จ");
    throwIfError(ledgerResult.error, "โหลดบัญชีรายรับรายจ่ายไม่สำเร็จ");
    throwIfError(withdrawalResult.error, "โหลดคำขอถอนเงินไม่สำเร็จ");
    throwIfError(orderResult.error, "โหลดออเดอร์ไม่สำเร็จ");
    throwIfError(serviceResult.error, "โหลดบริการไม่สำเร็จ");

    const profiles = profileResult.data || [];
    const emailById = new Map(profiles.map((item) => [item.id, item.email]));
    const withdrawals = (withdrawalResult.data || []).map(item => ({ ...item, email: emailById.get(item.user_id) || null }));
    const topups = await Promise.all((topupResult.data || []).map(async (item) => {
      let slipUrl = "";
      if (item.slip_path) {
        const { data: signed, error } = await sb.storage
          .from("payment-slips")
          .createSignedUrl(item.slip_path, 900);
        if (!error) slipUrl = signed?.signedUrl || "";
      }
      return { ...item, email: emailById.get(item.user_id) || null, slip_url: slipUrl };
    }));

    const approved = topups.filter((item) => item.status === "approved");
    const dailyIncome = [];
    for (let i = 13; i >= 0; i -= 1) {
      const date = new Date();
      date.setHours(0, 0, 0, 0);
      date.setDate(date.getDate() - i);
      const key = date.toISOString().slice(0, 10);
      dailyIncome.push({
        day: key.slice(5),
        total: approved
          .filter((item) => item.reviewed_at?.slice(0, 10) === key)
          .reduce((sum, item) => sum + Number(item.amount || 0), 0),
      });
    }

    state = {
      stats: {
        approved_income: approved.reduce((sum, item) => sum + Number(item.amount || 0), 0),
        total_credit_balance: profiles.reduce((sum, item) => sum + Number(item.credit_balance || 0), 0),
        pending_topups: topups.filter((item) => item.status === "pending").length,
        pending_withdrawals: withdrawals.filter((item) => item.status === "pending").length,
        users: profiles.length,
      },
      daily_income: dailyIncome,
      topups,
      users: profiles,
      ledger: ledgerResult.data || [],
      withdrawals,
      orders: (orderResult.data || []).map(item => ({...item,email:emailById.get(item.user_id)||null})),
      services: serviceResult.data || [],
    };

    render();
  } catch (error) {
    console.error("Dashboard load failed:", error);
    toast(error.message || "โหลดข้อมูลไม่สำเร็จ");
  }
}

function render() {
  const stats = state.stats || {};
  $("#statIncome").textContent = money(stats.approved_income);
  $("#statCredits").textContent = money(stats.total_credit_balance);
  $("#statPending").textContent = stats.pending_topups || 0;
  $("#statUsers").textContent = stats.users || 0;
  $("#pendingChip").textContent = `${stats.pending_topups || 0} pending`;
  if ($("#withdrawPendingChip")) $("#withdrawPendingChip").textContent = `${stats.pending_withdrawals || 0} pending`;
  renderChart();
  renderRecent();
  renderTopups();
  renderWithdrawals();
  renderOrders();
  renderUsers();
  renderServices();
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

function renderWithdrawals() {
  const items = state.withdrawals || [];
  const box = $("#withdrawRows");
  if (!box) return;
  box.innerHTML = items.map((item) => {
    const actions = item.status === "pending"
      ? `<button class="btn good" onclick="reviewWithdrawal('${item.id}','approve')">อนุมัติ</button> <button class="btn bad" onclick="reviewWithdrawal('${item.id}','reject')">ปฏิเสธ</button>`
      : "-";
    return `<tr><td>${item.email || "-"}<small>${String(item.user_id||"").slice(0,8)}</small></td><td><b>${money(item.amount)}</b></td><td>${item.payout_method === "truemoney" ? "TrueMoney" : "ธนาคาร"}</td><td>${item.payout_account || "-"}<small>${item.payout_name || "-"}</small></td><td>${new Date(item.created_at).toLocaleString("th-TH")}</td><td><span class="status ${item.status}">${item.status}</span></td><td>${actions}</td></tr>`;
  }).join("") || '<tr><td colspan="7">ไม่มีคำขอถอน</td></tr>';
}

async function reviewWithdrawal(id, mode) {
  const note = prompt(mode === "approve" ? "หมายเหตุการอนุมัติ" : "เหตุผลที่ปฏิเสธ") || "";
  try {
    const rpcName = mode === "approve" ? "admin_approve_withdrawal_simple" : "admin_reject_withdrawal_simple";
    const { error } = await sb.rpc(rpcName, { p_request_id: id, p_note: note });
    throwIfError(error, "ดำเนินการคำขอถอนไม่สำเร็จ");
    toast(mode === "approve" ? "อนุมัติและหักเครดิตแล้ว" : "ปฏิเสธคำขอถอนแล้ว");
    await load();
  } catch (error) { toast(error.message); }
}


function renderOrders() {
  const items = state.orders || [];
  const box = $("#orderRows"); if (!box) return;
  const active = items.filter(x => !["completed","cancelled"].includes(x.status)).length;
  if ($("#orderPendingChip")) $("#orderPendingChip").textContent = `${active} active`;
  box.innerHTML = items.map(item => {
    const next = item.status === "pending" ? `<button class="btn good" onclick="setOrderStatus('${item.id}','accepted')">รับงาน</button>` : item.status === "accepted" ? `<button class="btn primary" onclick="setOrderStatus('${item.id}','working')">เริ่มทำ</button>` : item.status === "working" ? `<button class="btn good" onclick="setOrderStatus('${item.id}','completed')">เสร็จแล้ว</button>` : "-";
    return `<tr><td><b>#${String(item.id).slice(0,8)}</b><small>${new Date(item.created_at).toLocaleString("th-TH")}</small></td><td>${item.email||"-"}<small>${item.customer_name||"-"} • ${item.contact||"-"}</small></td><td>${item.service_name||item.service_id}</td><td><b>${money(item.price)}</b></td><td style="max-width:280px;white-space:normal">${item.details||"-"}<small>${item.deadline?`กำหนด ${item.deadline}`:""}</small></td><td><span class="status ${item.status==='completed'?'approved':item.status==='cancelled'?'rejected':'pending'}">${item.status}</span></td><td>${next}</td></tr>`;
  }).join("") || '<tr><td colspan="7">ยังไม่มีออเดอร์</td></tr>';
}

async function setOrderStatus(id,status){
  try{const {error}=await sb.rpc("admin_update_order_status",{p_order_id:id,p_status:status,p_note:""});throwIfError(error,"อัปเดตออเดอร์ไม่สำเร็จ");toast("อัปเดตสถานะออเดอร์แล้ว");await load();}catch(error){toast(error.message);}
}

function renderUsers() {
  const items = state.users || [];
  $("#userRows").innerHTML = items.map((item) => `
    <tr><td>${item.email || "-"}<small>${item.id}</small></td><td><b>${money(item.credit_balance)}</b></td><td>${new Date(item.created_at).toLocaleDateString("th-TH")}</td><td><button class="btn" onclick="selectUser('${item.id}')">เลือก</button></td></tr>`
  ).join("") || '<tr><td colspan="4">ไม่มีผู้ใช้</td></tr>';
}


function renderServices() {
  const box = $("#serviceRows"); if (!box) return;
  box.innerHTML = (state.services || []).map(item => `
    <tr><td><b>${item.name}</b><small>${item.slug}</small></td><td>${money(item.price)}</td><td>${item.is_active ? '<span class="status approved">เปิดขาย</span>' : '<span class="status rejected">ปิดขาย</span>'}</td><td>${item.sort_order ?? 0}</td><td><button class="btn" onclick='editService(${JSON.stringify(item)})'>แก้ไข</button></td></tr>`
  ).join("") || '<tr><td colspan="5">ยังไม่มีบริการ</td></tr>';
}

function editService(item) {
  $("#serviceId").value = item.id || "";
  $("#serviceSlug").value = item.slug || "";
  $("#serviceName").value = item.name || "";
  $("#serviceDescription").value = item.description || "";
  $("#servicePrice").value = item.price || 0;
  $("#serviceActive").checked = !!item.is_active;
  $("#serviceSort").value = item.sort_order || 0;
}

async function saveService() {
  try {
    const payload = {
      p_id: $("#serviceId").value || null, p_slug: $("#serviceSlug").value.trim(),
      p_name: $("#serviceName").value.trim(), p_description: $("#serviceDescription").value.trim(),
      p_price: Number($("#servicePrice").value), p_is_active: $("#serviceActive").checked,
      p_sort_order: Number($("#serviceSort").value || 0)
    };
    if (!payload.p_slug || !payload.p_name || payload.p_price < 1) throw new Error("กรอกข้อมูลบริการให้ครบ");
    const { error } = await sb.rpc("admin_save_service", payload);
    throwIfError(error, "บันทึกบริการไม่สำเร็จ");
    toast("บันทึกบริการแล้ว"); clearServiceForm(); await load();
  } catch (error) { toast(error.message); }
}
function clearServiceForm(){ ["serviceId","serviceSlug","serviceName","serviceDescription","servicePrice","serviceSort"].forEach(id=>$("#"+id).value=""); $("#serviceActive").checked=true; }
window.editService = editService;

function renderLedger() {
  const items = state.ledger || [];
  $("#ledgerRows").innerHTML = items.map((item) => `
    <tr><td><span class="status ${item.amount >= 0 ? "approved" : "rejected"}">${item.amount >= 0 ? "รายรับ" : "รายจ่าย"}</span></td><td><b>${item.amount >= 0 ? "+" : ""}${money(item.amount)}</b></td><td>${item.note || "-"}</td><td>${new Date(item.created_at).toLocaleString("th-TH")}</td></tr>`
  ).join("") || '<tr><td colspan="4">ไม่มีรายการ</td></tr>';
}

async function review(id, mode) {
  const note = prompt(mode === "approve" ? "หมายเหตุการอนุมัติ (ไม่บังคับ)" : "เหตุผลที่ปฏิเสธ") || "";
  try {
    const rpcName = mode === "approve" ? "admin_approve_topup_simple" : "admin_reject_topup_simple";
    const { error } = await sb.rpc(rpcName, { p_request_id: id, p_note: note });
    throwIfError(error, "ดำเนินการไม่สำเร็จ");
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
    const userId = $("#adjustUserId").value.trim();
    const amount = Number($("#adjustAmount").value);
    if (!userId || !Number.isFinite(amount) || amount === 0) throw new Error("กรอกผู้ใช้และจำนวนเครดิตให้ถูกต้อง");

    const { error } = await sb.rpc("admin_adjust_credit_simple", {
      p_user_id: userId,
      p_amount: amount,
      p_note: $("#adjustNote").value.trim(),
    });
    throwIfError(error, "ปรับเครดิตไม่สำเร็จ");
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
    const amount = Number($("#ledgerAmount").value);
    const note = $("#ledgerNote").value.trim();
    if (!Number.isFinite(amount) || amount === 0) throw new Error("กรอกจำนวนเงินให้ถูกต้อง");

    const { error } = await sb.rpc("admin_add_ledger_simple", { p_amount: amount, p_note: note });
    throwIfError(error, "เพิ่มรายการบัญชีไม่สำเร็จ");
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
window.reviewWithdrawal = reviewWithdrawal;

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
$("#serviceSaveBtn")?.addEventListener("click", saveService);
$("#serviceNewBtn")?.addEventListener("click", clearServiceForm);
$("#logoutBtn")?.addEventListener("click", async () => {
  await sb.auth.signOut();
  location.href = "index.html";
});

boot();
