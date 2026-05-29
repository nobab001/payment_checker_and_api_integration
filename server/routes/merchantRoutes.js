"use strict";

const {
  listMerchants,
  getMerchantById,
  createMerchant,
  updateMerchant,
  saveCheckoutLayout,
  regenerateApiKey,
  maskApiKeyId,
  publicGatewayBase,
} = require("../services/merchantService");
const { verifyPaymentForMerchant } = require("../services/merchantVerifyService");
const { merchantApiAuth } = require("../middleware/merchantApiAuth");

function registerMerchantRoutes(app, deps) {
  const { authMiddleware, pool, verifyUserPin, isValidPinFormat } = deps;

  /** JWT — list integrated sites */
  app.get("/api/merchants", authMiddleware, async (req, res) => {
    try {
      const rows = await listMerchants(req.userId);
      const base = publicGatewayBase(req);
      return res.json({
        success: true,
        merchants: rows.map((m) => ({
          id: m.id,
          site_name: m.site_name,
          domain_address: m.domain_address,
          slug: m.slug,
          api_key_id: maskApiKeyId(m.api_key_id),
          is_active: m.is_active,
          gateway_url: `${base}/checkout/${m.slug}`,
          created_at: m.created_at,
        })),
      });
    } catch (e) {
      console.error("[merchants list]", e.message);
      return res
        .status(e.statusCode || 500)
        .json({ success: false, message: e.message });
    }
  });

  app.post("/api/merchants", authMiddleware, async (req, res) => {
    const { site_name, domain_address, gateway_username } = req.body ?? {};
    if (!site_name || !String(site_name).trim()) {
      return res.status(400).json({ success: false, message: "site_name required" });
    }
    try {
      const { merchant, apiSecret } = await createMerchant(req.userId, {
        siteName: site_name,
        domainAddress: domain_address,
        gatewayUsername: gateway_username || String(req.userId),
      });
      const base = publicGatewayBase(req);
      return res.status(201).json({
        success: true,
        merchant: {
          id: merchant.id,
          site_name: merchant.site_name,
          domain_address: merchant.domain_address,
          slug: merchant.slug,
          api_key_id: merchant.api_key_id,
          api_secret: apiSecret,
          gateway_url: `${base}/checkout/${merchant.slug}`,
          is_active: merchant.is_active,
        },
        message: "API secret shown once — store it securely.",
      });
    } catch (e) {
      console.error("[merchants create]", e.message);
      return res.status(500).json({ success: false, message: e.message });
    }
  });

  app.get("/api/merchants/:id", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    const m = await getMerchantById(req.userId, id);
    if (!m) return res.status(404).json({ success: false, message: "Not found" });
    const base = publicGatewayBase(req);
    return res.json({
      success: true,
      merchant: {
        id: m.id,
        site_name: m.site_name,
        domain_address: m.domain_address,
        slug: m.slug,
        api_key_id: maskApiKeyId(m.api_key_id),
        gateway_username: m.gateway_username || String(req.userId),
        gateway_url: `${base}/checkout/${m.slug}`,
        checkout_layout: m.checkout_layout,
        is_active: m.is_active,
      },
    });
  });

  app.patch("/api/merchants/:id", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    const { is_active, domain_address, site_name } = req.body ?? {};
    const m = await updateMerchant(req.userId, id, {
      isActive: is_active,
      domainAddress: domain_address,
      siteName: site_name,
    });
    if (!m) return res.status(404).json({ success: false, message: "Not found" });
    return res.json({ success: true, merchant: m });
  });

  app.put("/api/merchants/:id/checkout-layout", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    const layout = req.body?.checkout_layout ?? req.body;
    if (!layout || typeof layout !== "object") {
      return res.status(400).json({ success: false, message: "checkout_layout required" });
    }
    const row = await saveCheckoutLayout(req.userId, id, layout);
    if (!row) return res.status(404).json({ success: false, message: "Not found" });
    return res.json({ success: true });
  });

  app.post("/api/merchants/:id/regenerate-key", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    const pin = String(req.body?.pin ?? "").trim();
    if (!isValidPinFormat(pin)) {
      return res.status(400).json({ success: false, message: "Invalid PIN format" });
    }
    try {
      const [users] = await pool.query("SELECT * FROM users WHERE id = ? LIMIT 1", [
        req.userId,
      ]);
      if (!users.length || !verifyUserPin(users[0], pin)) {
        return res.status(403).json({ success: false, message: "Incorrect security PIN" });
      }
      const result = await regenerateApiKey(req.userId, id);
      if (!result) return res.status(404).json({ success: false, message: "Not found" });
      return res.json({
        success: true,
        api_key_id: result.merchant.api_key_id,
        api_secret: result.apiSecret,
        message: "New secret shown once — store it securely.",
      });
    } catch (e) {
      console.error("[merchants regenerate]", e.message);
      return res.status(500).json({ success: false, message: e.message });
    }
  });

  /** Merchant server-to-server verify */
  app.post("/api/v1/merchant/verify-payment", merchantApiAuth, async (req, res) => {
    const b = req.body ?? {};
    const result = await verifyPaymentForMerchant({
      merchant: req.merchant,
      trxId: b.trx_id,
      amount: b.amount,
      merchantOrderId: b.merchant_order_id,
      receiverNumber: b.receiver_number,
      idempotencyKey: req.headers["idempotency-key"],
    });
    return res.status(result.status).json(result.body);
  });
}

module.exports = { registerMerchantRoutes };
