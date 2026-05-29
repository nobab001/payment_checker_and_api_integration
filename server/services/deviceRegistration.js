"use strict";

const { rowToDeviceJson } = require("../utils/deviceRowJson");
const { emitApprovalRequestToParents } = require("../socket/deviceSocket");

/**
 * Register or refresh a hardware device for a user account.
 * First device → is_parent=1, status=active. Later devices → pending until parent approves.
 */
async function registerOrUpdateDevice(pool, io, opts) {
  const userId = Number(opts.userId);
  const deviceId = String(opts.deviceId || "").trim();
  const deviceName =
    String(opts.deviceName || "My Phone").trim() || "My Phone";
  const deviceModel = String(opts.deviceModel || "").trim();
  if (!userId || !deviceId) {
    throw new Error("userId and deviceId required");
  }

  const [[{ cnt }]] = await pool.query(
    `SELECT COUNT(*) AS cnt FROM devices WHERE user_id = ?`,
    [userId]
  );
  const isFirstAccountDevice = Number(cnt) === 0;

  const [existing] = await pool.query(
    `SELECT * FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
    [userId, deviceId]
  );

  const wasNew = !existing.length;

  if (existing.length) {
    await pool.query(
      `UPDATE devices SET
         device_name = ?,
         device_model = IF(? <> '', ?, device_model),
         last_seen_at = CURRENT_TIMESTAMP,
         updated_at = CURRENT_TIMESTAMP
       WHERE id = ?`,
      [deviceName, deviceModel, deviceModel, existing[0].id]
    );
  } else {
    const status = isFirstAccountDevice ? "active" : "pending";
    const isParent = isFirstAccountDevice ? 1 : 0;
    await pool.query(
      `INSERT INTO devices (user_id, device_id, device_name, device_model, status, is_parent, last_seen_at)
       VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
      [userId, deviceId, deviceName, deviceModel, status, isParent]
    );
  }

  const [rows] = await pool.query(
    `SELECT * FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
    [userId, deviceId]
  );
  const row = rows[0];
  const json = rowToDeviceJson(row);

  if (wasNew && String(row.status) === "pending" && io) {
    await emitApprovalRequestToParents(io, userId, json);
  }

  return {
    device: json,
    isNew: wasNew,
    requiresApproval: String(row.status) === "pending",
  };
}

module.exports = { registerOrUpdateDevice };
