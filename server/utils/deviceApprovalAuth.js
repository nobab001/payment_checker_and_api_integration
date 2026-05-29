"use strict";

const { verifyUserPin, upgradePinHashIfNeeded } = require("./pinAuth");

function callerHardwareFrom(req) {
  return String(req.headers["x-device-id"] || req.body?.deviceId || "").trim();
}

function approvalPinFrom(req) {
  return String(
    req.body?.pin ||
      req.body?.securityPin ||
      req.headers["x-device-approval-pin"] ||
      ""
  ).trim();
}

/**
 * Hybrid approval auth:
 * - Caller hardware matches account parent row → no PIN (parent phone).
 * - Else → valid account signup PIN (JWT user) is enough — child / non-parent
 *   can approve pending devices without holding the parent handset.
 */
async function authorizeDeviceManagerAction(pool, req) {
  const hw = callerHardwareFrom(req);
  const pin = approvalPinFrom(req);

  if (hw) {
    const [parents] = await pool.query(
      `SELECT id FROM devices WHERE user_id = ? AND device_id = ? AND is_parent = 1 LIMIT 1`,
      [req.userId, hw]
    );
    if (parents.length) {
      return { ok: true, via: "parent_device" };
    }
  }

  if (!pin) {
    if (!hw) {
      return {
        ok: false,
        status: 400,
        message:
          "Send X-Device-Id, or provide Security PIN in JSON body or X-Device-Approval-Pin header",
        requiresPin: true,
      };
    }
    return {
      ok: false,
      status: 403,
      message: "Security PIN required (account signup PIN)",
      requiresPin: true,
    };
  }

  const [users] = await pool.query("SELECT * FROM users WHERE id = ? LIMIT 1", [req.userId]);
  if (!users.length || !verifyUserPin(users[0], pin)) {
    return { ok: false, status: 403, message: "Invalid security PIN" };
  }
  await upgradePinHashIfNeeded(pool, req.userId, pin);
  return { ok: true, via: "account_pin" };
}

module.exports = { authorizeDeviceManagerAction, callerHardwareFrom, approvalPinFrom };
