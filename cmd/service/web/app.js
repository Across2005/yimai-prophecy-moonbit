// 译脉·先知 2.0 工作台 —— 消费 cmd/service 13 端点
"use strict";

// ---------- 基础设施 ----------
async function api(path, body) {
  try {
    const resp = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {}),
    });
    return { code: resp.status, json: await resp.json().catch(() => null) };
  } catch (e) {
    return { code: 0, json: { error: "无法连接服务（127.0.0.1:8787）。请先运行：moon run cmd/service --target native" } };
  }
}

function esc(s) {
  if (s === null || s === undefined) return "";
  return String(s).replace(/[&<>"']/g, c => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

function num(x, d = 4) { return (Number(x) || 0).toFixed(d); }

// toast 反馈
function toast(msg, type) {
  const box = document.getElementById("toast");
  const el = document.createElement("div");
  el.className = "toast " + (type || "info");
  el.textContent = msg;
  box.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}

// ---------- ① TM 模糊检索 ----------
async function fuzzyMatch() {
  const box = document.getElementById("fmResult");
  box.innerHTML = '<span class="hint">检索中…</span>';
  const q = document.getElementById("fmQuery").value.trim();
  if (!q) { box.innerHTML = '<span class="hint">请输入 query，或点「示例」。</span>'; return; }
  const r = await api("/api/fuzzy_match", {
    query: q,
    k: parseInt(document.getElementById("fmK").value) || 3,
    threshold: parseFloat(document.getElementById("fmThr").value) || 0.5,
  });
  if (r.code !== 200) {
    box.innerHTML = `<span class="violation">⚠ ${esc(r.json && r.json.error) || ("HTTP " + r.code)}</span>`;
    toast(r.json && r.json.error || ("HTTP " + r.code), "err");
    return;
  }
  const items = r.json || [];
  if (!items.length) {
    box.innerHTML = '<span class="hint">无匹配（阈值内）。先到 ③ 记录步骤灌入记忆，或降低 threshold 重试。</span>';
    return;
  }
  box.innerHTML = items.map(it => `
    <div class="item">
      <div class="src">${esc(it.source)}</div>
      <div class="tgt">→ ${esc(it.target)}</div>
      <div class="score">match_pct ${num(it.match_pct, 2)}% · score ${num(it.score)}</div>
      <div class="meta">sim_token ${num(it.sim_token)} · sim_tfidf ${num(it.sim_tfidf)} · sim_char ${num(it.sim_char)} · sim_ngram ${num(it.sim_ngram)} · sim_tokenset ${num(it.sim_tokenset)}</div>
    </div>`).join("");
}

function fmExample() {
  document.getElementById("fmQuery").value = "电池包热管理方案";
  document.getElementById("fmK").value = "3";
  document.getElementById("fmThr").value = "0.5";
  toast("已填入示例，正在检索…", "info");
  fuzzyMatch();
}

// ---------- ② 术语一致性校验 ----------
async function checkTerms() {
  const box = document.getElementById("ctResult");
  box.innerHTML = '<span class="hint">校验中…</span>';
  const r = await api("/api/check_terms", {
    source: document.getElementById("ctSrc").value.trim(),
    target: document.getElementById("ctTgt").value.trim(),
  });
  if (r.code !== 200) {
    box.innerHTML = `<span class="violation">⚠ ${esc(r.json && r.json.error) || ("HTTP " + r.code)}</span>`;
    toast("校验失败：" + (r.json && r.json.error || r.code), "err");
    return;
  }
  const viol = r.json || [];
  if (!viol.length) { box.innerHTML = '<span class="score">✓ 术语一致，无违规。</span>'; toast("✓ 术语一致", "ok"); return; }
  box.innerHTML = viol.map(v => `
    <div class="item violation">
      术语「${esc(v.term)}」→ 期望「${esc(v.expected)}」<span class="meta">mid=${esc(v.mid)}</span>
    </div>`).join("");
  toast(`发现 ${viol.length} 处术语违规`, "err");
}

function ctExample() {
  document.getElementById("ctSrc").value = "install the sensor";
  document.getElementById("ctTgt").value = "安装设备";
  toast("已填入示例（sensor 漏译），正在校验…", "info");
  checkTerms();
}

async function concordance() {
  const box = document.getElementById("ccResult");
  box.innerHTML = '<span class="hint">检索中…</span>';
  const term = document.getElementById("ccTerm").value.trim();
  if (!term) { box.innerHTML = '<span class="hint">请输入术语。</span>'; return; }
  const r = await api("/api/concordance", {
    term,
    k: parseInt(document.getElementById("ccK").value) || 3,
  });
  if (r.code !== 200) {
    box.innerHTML = `<span class="violation">⚠ ${esc(r.json && r.json.error) || ("HTTP " + r.code)}</span>`;
    return;
  }
  const items = r.json || [];
  if (!items.length) { box.innerHTML = '<span class="hint">TM 中暂无含该术语的段。</span>'; return; }
  box.innerHTML = items.map(it => `
    <div class="item">
      <div class="src">${esc(it.source)}</div>
      <div class="tgt">→ ${esc(it.target)}</div>
      <div class="score">hits ${esc(it.hits)}</div>
    </div>`).join("");
}

// ---------- ③ 预测 / 证据链 / 反馈 ----------
async function predict() {
  const box = document.getElementById("prResult");
  box.innerHTML = '<span class="hint">预测中…</span>';
  const r = await api("/api/predict", { k: parseInt(document.getElementById("prK").value) || 3 });
  if (r.code !== 200) {
    box.innerHTML = `<span class="violation">⚠ ${esc(r.json && r.json.error) || ("HTTP " + r.code)}</span>`;
    return;
  }
  const preds = (r.json && r.json.predictions) || [];
  const conf = r.json ? r.json.confidence : 0;
  if (!preds.length) {
    box.innerHTML = `<div class="hint">无可预测步骤（记忆为空）。点「示例」灌入两步工作流，或在下框 observe 记录步骤。</div>`;
    return;
  }
  box.innerHTML = `
    <div class="hint" style="margin-bottom:6px">confidence ${num(conf)} · uncertainty ${num(r.json.uncertainty)}</div>
    ${preds.map(p => `
      <div class="item">
        <div class="src">${esc(p.text)} <span class="score">prob ${num(p.prob)}</span></div>
        <div class="path">${esc((p.path || []).map(x => x.from + "→").join(""))}${esc(p.id || "")}</div>
        <div class="flex">
          <button class="mini" onclick="explain('${esc(p.id)}')">白盒</button>
          <button class="mini ok-btn" onclick="reward('${esc(p.id)}',1)">采纳 +1</button>
          <button class="mini bad-btn" onclick="reward('${esc(p.id)}',-1)">拒绝 -1</button>
        </div>
        <div id="ex-${esc(p.id)}"></div>
      </div>`).join("")}`;
}

function prExample() {
  (async () => {
    await api("/api/observe", { text: "解析源文件结构", mtype: "step" });
    await api("/api/observe", { text: "提取核心术语表并锁定", mtype: "step" });
    toast("已灌入两步工作流，正在预测第三步…", "info");
    predict();
    refreshCount();
  })();
}

async function explain(mid) {
  const box = document.getElementById("ex-" + mid);
  if (!box) return;
  box.innerHTML = '<span class="hint">加载…</span>';
  const r = await api("/api/explain", { mid });
  if (r.code !== 200) {
    box.innerHTML = `<span class="violation">⚠ HTTP ${r.code}</span>`;
    return;
  }
  const j = r.json || {};
  const vb = j.value_breakdown || {};
  box.innerHTML = `
    <details open>
      <summary>白盒卡片 ${esc(j.id)}</summary>
      <div class="meta">文本：${esc(j.text)}</div>
      <div class="meta">predictive_value ${num(vb.predictive_value)} · u_past ${num(vb.u_past)} · u_pred ${num(vb.u_pred)} · u_feedback ${num(vb.u_feedback)} · c_graph ${num(vb.c_graph)}</div>
      <div class="meta">activation_path: ${esc(JSON.stringify(j.activation_path || []))}</div>
      <div class="meta">prediction_path: ${esc(JSON.stringify(j.prediction_path || []))}</div>
    </details>`;
}

async function reward(mid, score) {
  const r = await api("/api/reward", { mid, score });
  if (r.code === 200) {
    toast(`✓ 已${score > 0 ? "采纳" : "拒绝"} ${mid}（predictive_value 已更新并落盘）`, "ok");
    refreshCount();
  } else {
    toast(`反馈失败：${r.json ? r.json.error : r.code}`, "err");
  }
}

async function observe() {
  const box = document.getElementById("obResult");
  const text = document.getElementById("obText").value.trim();
  if (!text) { box.innerHTML = '<span class="hint">请输入步骤文本。</span>'; return; }
  box.innerHTML = '<span class="hint">写入中…</span>';
  const r = await api("/api/observe", { text, mtype: "step" });
  if (r.code !== 200) {
    box.innerHTML = `<span class="violation">⚠ ${esc(r.json && r.json.error) || ("HTTP " + r.code)}</span>`;
    return;
  }
  box.innerHTML = `<span class="score">✓ 已记录 ${esc(r.json.mid)}，记忆 + 转移已落盘。</span>`;
  document.getElementById("obText").value = "";
  toast(`✓ 已记录 ${r.json.mid}`, "ok");
  refreshCount();
}

async function refreshCount() {
  try {
    const r = await fetch("/api/tm_count");
    if (!r.ok) return;
    const j = await r.json();
    document.getElementById("tmCount").textContent = "TM: " + (j.tm_count ?? "--");
  } catch (e) { /* 服务未启动时静默 */ }
}

refreshCount();
