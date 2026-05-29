"use strict";

const { getMerchantBySlug } = require("../services/merchantService");
const { verifyPaymentForMerchant } = require("../services/merchantVerifyService");

const BLOCK_TITLES = {
  bkash_personal:
    "বিকাশ পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন",
  nagad_personal:
    "নগদ পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন",
  rocket_personal:
    "রকেট পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন",
  upay_personal:
    "উপায় পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন",
  bkash_agent: "বিকাশ এজেন্ট — নিচের নাম্বারগুলোতে ক্যাশ আউট করুন",
  nagad_agent: "নগদ এজেন্ট — নিচের নাম্বারগুলোতে ক্যাশ আউট করুন",
  bank_accounts:
    "ব্যাংক — নিচের অ্যাকাউন্ট নাম্বারগুলোতে অবশ্যই NPSB করবেন",
};

function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderBlocksHtml(layout) {
  const order = layout?.blockOrder || Object.keys(BLOCK_TITLES);
  const blocks = layout?.blocks || {};
  let html = "";

  for (const blockId of order) {
    const block = blocks[blockId] || {};
    const title = block.title || BLOCK_TITLES[blockId] || blockId;
    const numbers = (block.numbers || []).filter((n) => n.enabled !== false);
    if (!numbers.length && blockId !== "bank_accounts") continue;

    html += `<section class="block"><h2>${escapeHtml(title)}</h2><ul>`;

    if (blockId === "bank_accounts") {
      for (const row of numbers) {
        const label = [
          row.bankName,
          row.accountName,
          row.branch,
          row.phone || row.accountNumber,
        ]
          .filter(Boolean)
          .join(" — ");
        html += `<li>${escapeHtml(label || "—")}</li>`;
      }
    } else {
      for (const row of numbers) {
        html += `<li>${escapeHtml(row.phone || "")}</li>`;
      }
    }
    html += "</ul></section>";
  }
  return html || "<p class=\"muted\">কোনো নম্বর ম্যাপ করা হয়নি। মার্চেন্ট প্যানেল থেকে Checkout Designer সেভ করুন।</p>";
}

function pageShell({ title, body, slug, flash }) {
  return `<!DOCTYPE html>
<html lang="bn">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>${escapeHtml(title)}</title>
  <style>
    *{box-sizing:border-box}
    body{font-family:system-ui,sans-serif;margin:0;background:#f5f7fa;color:#1a1a2e}
    .wrap{max-width:520px;margin:0 auto;padding:20px}
    h1{font-size:1.25rem;color:#1A237E}
    .block{background:#fff;border-radius:12px;padding:16px;margin:12px 0;box-shadow:0 1px 4px rgba(0,0,0,.08)}
    .block h2{font-size:.95rem;margin:0 0 10px;color:#333}
    .block ul{margin:0;padding-left:1.2rem}
    .flash{padding:12px;border-radius:8px;margin-bottom:12px}
    .flash.ok{background:#e8f5e9;color:#2e7d32}
    .flash.err{background:#ffebee;color:#c62828}
    form{background:#fff;padding:16px;border-radius:12px;margin-top:16px}
    label{display:block;margin:8px 0 4px;font-weight:600;font-size:.9rem}
    input{width:100%;padding:10px;border:1px solid #ccc;border-radius:8px;font-size:1rem}
    button{width:100%;margin-top:12px;padding:12px;background:#1A237E;color:#fff;border:0;border-radius:8px;font-size:1rem;cursor:pointer}
    .muted{color:#888;font-size:.9rem}
  </style>
</head>
<body>
  <div class="wrap">
    <h1>${escapeHtml(title)}</h1>
    ${flash || ""}
    ${body}
    <form method="post" action="/checkout/${escapeHtml(slug)}/verify">
      <label>ট্রানজেকশন আইডি (TrxID)</label>
      <input name="trx_id" required placeholder="TrxID লিখুন"/>
      <label>টাকার পরিমাণ</label>
      <input name="amount" type="number" step="0.01" required placeholder="1250"/>
      <label>অর্ডার নম্বর (ঐচ্ছিক)</label>
      <input name="merchant_order_id" placeholder="ORDER-123"/>
      <button type="submit">পেমেন্ট যাচাই করুন</button>
    </form>
  </div>
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
    const layout =
      typeof merchant.checkout_layout === "object"
        ? merchant.checkout_layout
        : JSON.parse(merchant.checkout_layout || "{}");
    const blocksHtml = renderBlocksHtml(layout);
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

    const layout =
      typeof merchant.checkout_layout === "object"
        ? merchant.checkout_layout
        : JSON.parse(merchant.checkout_layout || "{}");
    const blocksHtml = renderBlocksHtml(layout);
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
    res.status(result.status >= 400 ? 200 : 200).type("html").send(html);
  });
}

module.exports = { registerCheckoutPublicRoutes, BLOCK_TITLES };
