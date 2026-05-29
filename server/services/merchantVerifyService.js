"use strict";

const { setMysqlPool, requirePool } = require("./merchantService");

// Re-export pool setter (verify uses same MySQL pool as merchants)
function initVerifyPool(pool) {
  setMysqlPool(pool);
}

const MSG_ALREADY_REDEEMED =
  "আপনার এই ট্রানজেকশন আইডিটি দিয়ে ইতিমধ্যেই আপনার অ্যাকাউন্টের পেমেন্ট বা টাকা অ্যাড করা হয়ে গেছে।";

const MSG_INVALID =
  "ট্রানজেকশন আইডি বা পরিমাণ সঠিক নয়। আবার চেক করে চেষ্টা করুন।";

function isSyntheticTrx(trxId) {
  const t = String(trxId || "").trim();
  return !t || t.startsWith("GEN");
}

async function verifyPaymentForMerchant({
  merchant,
  trxId,
  amount,
  merchantOrderId,
  receiverNumber,
  idempotencyKey,
}) {
  const trx = String(trxId || "").trim();
  const amt = parseFloat(amount);
  if (isSyntheticTrx(trx) || !Number.isFinite(amt) || amt <= 0) {
    return {
      status: 400,
      body: { success: false, code: "INVALID_REQUEST", message: MSG_INVALID },
    };
  }

  const accountId = merchant.account_id;
  const pool = requirePool();
  const conn = await pool.getConnection();

  try {
    await conn.beginTransaction();

    const params = [accountId, trx, amt];
    let recvClause = "";
    if (receiverNumber) {
      recvClause = " AND receiver_number = ?";
      params.push(String(receiverNumber).slice(0, 32));
    }

    const [rows] = await conn.query(
      `SELECT id, amount, is_used, provider_tag, sms_timestamp, full_sms, receiver_number
       FROM parsed_payments
       WHERE user_id = ?
         AND trx_id = ?
         AND amount = ?
         AND (is_used = 0 OR is_used IS NULL)
         ${recvClause}
       ORDER BY sms_timestamp DESC
       LIMIT 1
       FOR UPDATE`,
      params
    );

    if (!rows.length) {
      const [usedCheck] = await conn.query(
        `SELECT id, is_used FROM parsed_payments
         WHERE user_id = ? AND trx_id = ?
         ORDER BY sms_timestamp DESC LIMIT 1`,
        [accountId, trx]
      );
      await conn.rollback();
      if (usedCheck.length && usedCheck[0].is_used) {
        return {
          status: 409,
          body: {
            success: false,
            code: "TRX_ALREADY_REDEEMED",
            message: MSG_ALREADY_REDEEMED,
          },
        };
      }
      return {
        status: 404,
        body: { success: false, code: "PAYMENT_NOT_FOUND", message: MSG_INVALID },
      };
    }

    const pay = rows[0];
    await conn.query(
      `UPDATE parsed_payments
       SET is_used = 1, used_at = NOW(), used_by_merchant_id = ?
       WHERE user_id = ? AND id = ?`,
      [merchant.id, accountId, pay.id]
    );

    const orderId = String(merchantOrderId || `checkout-${Date.now()}`).slice(
      0,
      128
    );
    await conn.query(
      `INSERT INTO payment_redemptions
         (payment_id, account_id, merchant_id, merchant_order_id, trx_id, amount, idempotency_key)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        pay.id,
        accountId,
        merchant.id,
        orderId,
        trx,
        amt,
        idempotencyKey || null,
      ]
    );

    await conn.commit();

    return {
      status: 200,
      body: {
        success: true,
        code: "PAYMENT_VERIFIED",
        data: {
          trx_id: trx,
          amount: pay.amount,
          provider_tag: pay.provider_tag,
          receiver_number: pay.receiver_number,
          merchant_order_id: orderId,
          verified_at: new Date().toISOString(),
        },
      },
    };
  } catch (err) {
    await conn.rollback();
    if (err.code === "ER_DUP_ENTRY") {
      return {
        status: 409,
        body: {
          success: false,
          code: "TRX_ALREADY_REDEEMED",
          message: MSG_ALREADY_REDEEMED,
        },
      };
    }
    console.error("[merchantVerify]", err.message);
    return { status: 500, body: { success: false, message: "Verification failed" } };
  } finally {
    conn.release();
  }
}

module.exports = {
  initVerifyPool,
  verifyPaymentForMerchant,
  MSG_ALREADY_REDEEMED,
  MSG_INVALID,
  isSyntheticTrx,
};
