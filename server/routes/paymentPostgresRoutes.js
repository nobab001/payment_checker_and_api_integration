"use strict";

const {
  searchPaymentsCascading,
  insertPaymentPostgres,
} = require("../services/paymentSearchService");

function registerPaymentPostgresRoutes(app, authMiddleware) {
  /**
   * POST /api/payments/search
   * Cascading time windows on PostgreSQL (account_id = JWT user id).
   */
  app.post("/api/payments/search", authMiddleware, async (req, res) => {
    const accountId = req.userId;
    if (!accountId) {
      return res.status(401).json({ success: false, message: "Unauthorized" });
    }

    const b = req.body ?? {};
    const trx_id = String(b.trx_id ?? "").trim();
    const query = String(b.query ?? "").trim();
    const receiver_number = String(b.receiver_number ?? "").trim();
    const provider_tag = String(b.provider_tag ?? "").trim();

    if (!trx_id && query.length < 3) {
      return res.status(400).json({
        success: false,
        message: "trx_id or query (min 3 chars) required",
      });
    }

    try {
      const { window, results } = await searchPaymentsCascading({
        accountId,
        trxId: trx_id || null,
        query: query || null,
        receiverNumber: receiver_number || null,
        providerTag: provider_tag || null,
      });

      return res.json({
        success: true,
        window,
        results: results.map((r) => ({
          id: r.id,
          trx_id: r.trx_id,
          receiver_number: r.receiver_number,
          provider_tag: r.provider_tag,
          amount: r.amount,
          sender_number: r.sender_number,
          sms_timestamp: r.sms_timestamp,
          sms_date: r.sms_date,
          sms_time: r.sms_time,
          full_sms: r.full_sms,
          sim_slot: r.sim_slot,
        })),
      });
    } catch (err) {
      console.error("[payments/search]", err.message);
      return res.status(500).json({ success: false, message: "Search failed" });
    }
  });

}

module.exports = { registerPaymentPostgresRoutes };
