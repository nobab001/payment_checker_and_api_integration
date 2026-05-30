"use strict";

const { getMerchantBySlug, requirePool } = require("../services/merchantService");
const { verifyPaymentForMerchant } = require("../services/merchantVerifyService");

const BLOCK_TITLES = {
  bkash_personal: "বিকাশ পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন",
  nagad_personal: "নগদ পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন",
  rocket_personal: "রকেট পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন",
  upay_personal: "উপায় পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন",
  bkash_agent: "বিকাশ এজেন্ট — নিচের নাম্বারগুলোতে ক্যাশ আউট করুন",
  nagad_agent: "নগদ এজেন্ট — নিচের নাম্বারগুলোতে ক্যাশ আউট করুন",
  bank_accounts: "ব্যাংক — নিচের অ্যাকাউন্ট নাম্বারগুলোতে অবশ্যই NPSB করবেন",
};

const OPERATOR_ICONS = {
  bkash_personal: `<span class="icon bkash">bKash</span>`,
  nagad_personal: `<span class="icon nagad">Nagad</span>`,
  rocket_personal: `<span class="icon rocket">Rocket</span>`,
  upay_personal: `<span class="icon upay">Upay</span>`,
  bkash_agent: `<span class="icon bkash">bKash</span>`,
  nagad_agent: `<span class="icon nagad">Nagad</span>`,
  bank_accounts: `<span class="icon bank"><svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M12 2L2 7v2h20V7L12 2zm10 9H2v2h20v-2zm-18 4v5h3v-5H4zm6 0v5h3v-5h-3zm6 0v5h3v-5h-3zm4 7H2v2h20v-2z"/></svg> Bank</span>`,
};

function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderBlocksHtml(layout, activeSim1s, activeSim2s, activeBanks) {
  const order = layout?.blockOrder || Object.keys(BLOCK_TITLES);
  const blocks = layout?.blocks || {};
  let html = "";

  for (const blockId of order) {
    const block = blocks[blockId] || {};
    
    // Skip if block is explicitly disabled
    if (block.enabled === false) continue;

    const title = block.title || BLOCK_TITLES[blockId] || blockId;
    const rawNumbers = block.numbers || [];

    // Filter numbers dynamically: must be enabled in customizer AND active in handset settings
    const filteredNumbers = rawNumbers.filter((n) => {
      if (n.enabled === false) return false;
      
      if (blockId === "bank_accounts") {
        const key = `${n.bankName}_${n.phone}`;
        return activeBanks.has(key);
      } else {
        // Must match either SIM 1 or SIM 2 active numbers on handset
        return activeSim1s.has(n.phone) || activeSim2s.has(n.phone);
      }
    });

    // Limit to max 5 items per block
    const numbers = filteredNumbers.slice(0, 5);
    if (!numbers.length) continue;

    const iconHtml = OPERATOR_ICONS[blockId] || `<span class="icon">●</span>`;
    html += `<section class="block">
      <div class="block-header">
        ${iconHtml}
        <h2>${escapeHtml(title)}</h2>
      </div>
      <ul class="number-list">`;

    if (blockId === "bank_accounts") {
      for (const row of numbers) {
        const fullDetails = [
          row.bankName,
          row.accountName,
          row.branch,
          row.phone || row.accountNumber,
        ]
          .filter(Boolean)
          .join(" — ");
        const copyVal = row.phone || row.accountNumber || "";
        
        html += `
        <li class="copyable-item" onclick="copyToClipboard('${escapeHtml(copyVal)}', this)" title="ক্লিক করে অ্যাকাউন্ট নম্বর কপি করুন">
          <div class="info-row">
            <span class="bank-details">${escapeHtml(fullDetails)}</span>
            <span class="copy-badge">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
              কপি করুন
            </span>
          </div>
        </li>`;
      }
    } else {
      for (const row of numbers) {
        const copyVal = row.phone || "";
        html += `
        <li class="copyable-item" onclick="copyToClipboard('${escapeHtml(copyVal)}', this)" title="ক্লিক করে নম্বর কপি করুন">
          <div class="info-row">
            <span class="phone-number">${escapeHtml(copyVal)}</span>
            <span class="copy-badge">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
              কপি করুন
            </span>
          </div>
        </li>`;
      }
    }
    html += "</ul></section>";
  }

  return html || `<p class="muted-info">কোনো নম্বর ম্যাপ করা হয়নি বা সেট করা ডিভাইসটি অফলাইন রয়েছে।</p>`;
}

function pageShell({ title, body, slug, flash }) {
  return `<!DOCTYPE html>
<html lang="bn">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>${escapeHtml(title)} — Checkout</title>
  <style>
    :root {
      --primary: #1A237E;
      --primary-hover: #12185C;
      --bg: #F4F6F9;
      --card-bg: #FFFFFF;
      --text: #2c3e50;
      --muted: #7f8c8d;
      --shadow: 0 4px 15px rgba(0, 0, 0, 0.05);
      --border-radius: 12px;
      --green: #2e7d32;
      --red: #c62828;
    }
    * { box-sizing: border-box; outline: none; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      margin: 0;
      padding: 0;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
    }
    .container {
      max-width: 520px;
      margin: 0 auto;
      padding: 20px 16px;
    }
    header {
      text-align: center;
      margin-bottom: 20px;
    }
    header h1 {
      font-size: 1.5rem;
      font-weight: 700;
      color: var(--primary);
      margin: 0;
    }
    header p {
      font-size: 0.9rem;
      color: var(--muted);
      margin: 6px 0 0;
    }
    .flash {
      padding: 14px 16px;
      border-radius: var(--border-radius);
      margin-bottom: 20px;
      font-weight: 500;
      font-size: 0.95rem;
      box-shadow: var(--shadow);
    }
    .flash.ok {
      background: #e8f5e9;
      color: var(--green);
      border-left: 5px solid var(--green);
    }
    .flash.err {
      background: #ffebee;
      color: var(--red);
      border-left: 5px solid var(--red);
    }
    .verify-card {
      background: var(--card-bg);
      border-radius: var(--border-radius);
      padding: 20px;
      margin-bottom: 20px;
      box-shadow: var(--shadow);
      border: 1px solid rgba(0, 0, 0, 0.04);
    }
    .verify-card h3 {
      margin: 0 0 16px;
      font-size: 1.1rem;
      color: var(--primary);
      border-bottom: 2px solid #E8EAF6;
      padding-bottom: 8px;
    }
    .form-group {
      margin-bottom: 12px;
    }
    .form-group label {
      display: block;
      margin-bottom: 6px;
      font-weight: 600;
      font-size: 0.85rem;
      color: #34495e;
    }
    .form-group input {
      width: 100%;
      padding: 12px;
      border: 1px solid #dcdde1;
      border-radius: 8px;
      font-size: 1rem;
      transition: all 0.2s ease;
      background: #fafafa;
    }
    .form-group input:focus {
      border-color: var(--primary);
      background: #ffffff;
      box-shadow: 0 0 0 3px rgba(26, 35, 126, 0.1);
    }
    button.btn-verify {
      width: 100%;
      padding: 14px;
      background: var(--primary);
      color: #ffffff;
      border: 0;
      border-radius: 8px;
      font-size: 1rem;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.2s ease;
      margin-top: 8px;
    }
    button.btn-verify:hover {
      background: var(--primary-hover);
    }
    .block {
      background: var(--card-bg);
      border-radius: var(--border-radius);
      padding: 20px;
      margin-bottom: 16px;
      box-shadow: var(--shadow);
      border: 1px solid rgba(0, 0, 0, 0.04);
    }
    .block-header {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-bottom: 14px;
      border-bottom: 1px solid #f1f2f6;
      padding-bottom: 10px;
    }
    .block-header h2 {
      font-size: 0.95rem;
      margin: 0;
      color: #2c3e50;
      font-weight: 700;
      line-height: 1.4;
    }
    .icon {
      font-size: 0.75rem;
      font-weight: bold;
      color: #ffffff;
      padding: 3px 8px;
      border-radius: 20px;
      text-transform: uppercase;
      display: inline-flex;
      align-items: center;
      gap: 4px;
    }
    .icon.bkash { background: #D12053; }
    .icon.nagad { background: #F37021; }
    .icon.rocket { background: #8C3494; }
    .icon.upay { background: #005A9C; }
    .icon.bank { background: #4a54f1; }
    
    .number-list {
      list-style: none;
      padding: 0;
      margin: 0;
    }
    .copyable-item {
      padding: 12px 14px;
      background: #fafbfc;
      border: 1px solid #f1f2f6;
      border-radius: 8px;
      margin-bottom: 8px;
      cursor: pointer;
      transition: all 0.2s ease;
    }
    .copyable-item:hover {
      background: #eef2fe;
      border-color: #c5cae9;
      transform: translateY(-1px);
    }
    .copyable-item:last-child {
      margin-bottom: 0;
    }
    .info-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .phone-number {
      font-size: 1.15rem;
      font-weight: 700;
      letter-spacing: 0.5px;
      color: #1A237E;
    }
    .bank-details {
      font-size: 0.92rem;
      font-weight: 600;
      color: #2c3e50;
      line-height: 1.4;
    }
    .copy-badge {
      display: flex;
      align-items: center;
      gap: 4px;
      font-size: 0.75rem;
      font-weight: 700;
      color: var(--muted);
      background: #f1f2f6;
      padding: 4px 8px;
      border-radius: 6px;
      transition: all 0.2s ease;
    }
    .copyable-item:hover .copy-badge {
      background: var(--primary);
      color: #ffffff;
    }
    .toast {
      position: fixed;
      bottom: 30px;
      left: 50%;
      transform: translateX(-50%) translateY(100px);
      background: #323232;
      color: #ffffff;
      padding: 10px 24px;
      border-radius: 30px;
      font-size: 0.9rem;
      font-weight: 600;
      box-shadow: 0 4px 20px rgba(0,0,0,0.15);
      transition: transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
      z-index: 9999;
    }
    .toast.show {
      transform: translateX(-50%) translateY(0);
    }
    .muted-info {
      text-align: center;
      color: var(--muted);
      font-size: 0.9rem;
      margin: 20px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>${escapeHtml(title)}</h1>
      <p>পেমেন্ট চেকআউট গেটওয়ে</p>
    </header>

    ${flash || ""}

    <!-- Verification Card is strictly at the top -->
    <div class="verify-card">
      <h3>পেমেন্ট যাচাইকরণ</h3>
      <form method="post" action="/checkout/${escapeHtml(slug)}/verify">
        <div class="form-group">
          <label>ট্রানজেকশন আইডি (TrxID)</label>
          <input name="trx_id" required placeholder="TrxID লিখুন"/>
        </div>
        <div class="form-group">
          <label>টাকার পরিমাণ</label>
          <input name="amount" type="number" step="0.01" required placeholder="1250"/>
        </div>
        <div class="form-group">
          <label>অর্ডার নম্বর (ঐচ্ছিক)</label>
          <input name="merchant_order_id" placeholder="ORDER-123"/>
        </div>
        <button type="submit" class="btn-verify">পেমেন্ট যাচাই করুন</button>
      </form>
    </div>

    <!-- Active accounts list goes below -->
    ${body}
  </div>

  <div id="toast" class="toast">নম্বর কপি হয়েছে!</div>

  <script>
    function copyToClipboard(text, elem) {
      if (!text) return;
      navigator.clipboard.writeText(text).then(function() {
        const toast = document.getElementById("toast");
        toast.textContent = elem.classList.contains("bank-accounts") || text.length > 15 
          ? "অ্যাকাউন্ট নম্বর কপি হয়েছে!" 
          : "মোবাইল নম্বর কপি হয়েছে!";
        toast.classList.add("show");
        setTimeout(function() {
          toast.classList.remove("show");
        }, 2000);
      });
    }
  </script>
</body>
</html>`;
}

function registerCheckoutPublicRoutes(app) {
  app.get("/checkout/:slug", async (req, res) => {
    let merchant;
    try {
      merchant = await getMerchantBySlug(req.params.slug);
    } catch (e) {
      return res
        .status(e.statusCode || 503)
        .send("পেমেন্ট সার্ভিস সাময়িকভাবে অনুপলব্ধ। PostgreSQL চালু করুন।");
    }
    if (!merchant) {
      return res.status(404).send("Checkout page not found");
    }

    // 1. Fetch active devices and extract configured numbers
    const activeSim1s = new Set();
    const activeSim2s = new Set();
    const activeBanks = new Set();

    try {
      const pool = requirePool();
      const [devices] = await pool.query(
        "SELECT sim_settings, sim1_number, sim2_number FROM devices WHERE user_id = ? AND status = 'active'",
        [merchant.account_id]
      );

      for (const dev of devices) {
        let simSettings = {};
        if (dev.sim_settings) {
          try {
            simSettings = typeof dev.sim_settings === "string" 
              ? JSON.parse(dev.sim_settings) 
              : dev.sim_settings;
          } catch (_) {}
        }
        
        const sim1 = simSettings.sim1 || {};
        const sim2 = simSettings.sim2 || {};
        const bankAccounts = simSettings.bank_accounts || simSettings.bankAccounts || [];

        if (sim1.active !== false && dev.sim1_number && dev.sim1_number.trim().length >= 11) {
          activeSim1s.add(dev.sim1_number.trim());
        }
        if (sim2.active !== false && dev.sim2_number && dev.sim2_number.trim().length >= 11) {
          activeSim2s.add(dev.sim2_number.trim());
        }
        for (const bank of bankAccounts) {
          if (bank.phone) {
            activeBanks.add(`${bank.bankName}_${bank.phone}`);
          }
        }
      }
    } catch (e) {
      console.error("[checkoutPublicRoutes] failed to fetch active device settings:", e.message);
    }

    const layout =
      typeof merchant.checkout_layout === "object"
        ? merchant.checkout_layout
        : JSON.parse(merchant.checkout_layout || "{}");

    // 2. Render blocks checking active status dynamically
    const blocksHtml = renderBlocksHtml(layout, activeSim1s, activeSim2s, activeBanks);
    
    const html = pageShell({
      title: merchant.site_name,
      slug: merchant.slug,
      body: blocksHtml,
      flash: "",
    });
    res.type("html").send(html);
  });

  app.post("/checkout/:slug/verify", async (req, res) => {
    let merchant;
    try {
      merchant = await getMerchantBySlug(req.params.slug);
    } catch (e) {
      return res
        .status(e.statusCode || 503)
        .send("পেমেন্ট সার্ভিস সাময়িকভাবে অনুপলব্ধ।");
    }
    if (!merchant) {
      return res.status(404).send("Not found");
    }
    const trx_id = req.body?.trx_id;
    const amount = req.body?.amount;
    const merchant_order_id = req.body?.merchant_order_id;

    const result = await verifyPaymentForMerchant({
      merchant,
      trxId: trx_id,
      amount,
      merchantOrderId: merchant_order_id,
      receiverNumber: null,
      idempotencyKey: null,
    });

    // Re-fetch active devices for re-rendering checkout options on verification feedback
    const activeSim1s = new Set();
    const activeSim2s = new Set();
    const activeBanks = new Set();

    try {
      const pool = requirePool();
      const [devices] = await pool.query(
        "SELECT sim_settings, sim1_number, sim2_number FROM devices WHERE user_id = ? AND status = 'active'",
        [merchant.account_id]
      );

      for (const dev of devices) {
        let simSettings = {};
        if (dev.sim_settings) {
          try {
            simSettings = typeof dev.sim_settings === "string" 
              ? JSON.parse(dev.sim_settings) 
              : dev.sim_settings;
          } catch (_) {}
        }
        
        const sim1 = simSettings.sim1 || {};
        const sim2 = simSettings.sim2 || {};
        const bankAccounts = simSettings.bank_accounts || simSettings.bankAccounts || [];

        if (sim1.active !== false && dev.sim1_number && dev.sim1_number.trim().length >= 11) {
          activeSim1s.add(dev.sim1_number.trim());
        }
        if (sim2.active !== false && dev.sim2_number && dev.sim2_number.trim().length >= 11) {
          activeSim2s.add(dev.sim2_number.trim());
        }
        for (const bank of bankAccounts) {
          if (bank.phone) {
            activeBanks.add(`${bank.bankName}_${bank.phone}`);
          }
        }
      }
    } catch (e) {
      console.error("[checkoutPublicRoutes] failed to fetch active device settings on verify:", e.message);
    }

    const layout =
      typeof merchant.checkout_layout === "object"
        ? merchant.checkout_layout
        : JSON.parse(merchant.checkout_layout || "{}");
    const blocksHtml = renderBlocksHtml(layout, activeSim1s, activeSim2s, activeBanks);
    
    const ok = result.status === 200;
    const flash = `<div class="flash ${ok ? "ok" : "err"}">${escapeHtml(
      result.body.message || (ok ? "পেমেন্ট যাচাই সফল!" : result.body.code || "যাচাই ব্যর্থ")
    )}</div>`;

    const html = pageShell({
      title: merchant.site_name,
      slug: merchant.slug,
      body: blocksHtml,
      flash,
    });
    res.status(200).type("html").send(html);
  });
}

module.exports = { registerCheckoutPublicRoutes, BLOCK_TITLES };
