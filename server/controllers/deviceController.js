"use strict";

/**
 * Device CRUD, parent/child approval (`status`, `is_parent`), rename (`custom_name`).
 */

const {
  emitDeviceActivated,
  emitDeviceRejected,
  emitParentRoleChanged,
} = require("../socket/deviceSocket");
const { registerOrUpdateDevice } = require("../services/deviceRegistration");
const { rowToDeviceJson } = require("../utils/deviceRowJson");
const {
  parseSimSettingsRow,
  simSettingsToApi,
  bodyToSimSettings,
} = require("../utils/deviceSimSettings");
const { deviceNeedsSecurityPin } = require("../utils/deviceAuthPolicy");
const { verifyUserPin, upgradePinHashIfNeeded } = require("../utils/pinAuth");
const { authorizeDeviceManagerAction } = require("../utils/deviceApprovalAuth");

function parentHardwareFrom(req) {
  return String(req.headers["x-device-id"] || req.body?.deviceId || "").trim();
}

function recoveryKeyFrom(req) {
  return String(
    req.headers["x-parent-recovery-key"] ||
      req.headers["x-recovery-key"] ||
      req.body?.recoveryKey ||
      req.body?.recovery_key ||
      ""
  ).trim();
}

/**
 * Reassign account parent without the current parent handset (master recovery key).
 * Body: target_device_id | target_device_model | target_hardware_id (device_id column)
 */
async function authorizeParentRecovery(pool, req) {
  const expected = String(process.env.PARENT_RECOVERY_KEY || "").trim();
  const providedKey = recoveryKeyFrom(req);
  if (expected && providedKey && providedKey === expected) {
    return { ok: true, via: "recovery_key" };
  }

  const accountPin = String(
    req.body?.pin || req.body?.securityPin || req.body?.masterPin || ""
  ).trim();
  if (accountPin) {
    const [users] = await pool.query("SELECT * FROM users WHERE id = ? LIMIT 1", [req.userId]);
    if (users.length && verifyUserPin(users[0], accountPin)) {
      await upgradePinHashIfNeeded(pool, req.userId, accountPin);
      return { ok: true, via: "account_pin" };
    }
  }

  return { ok: false };
}

async function reassignParentWithRecoveryKey(pool, io, req, res) {
  const authz = await authorizeParentRecovery(pool, req);
  if (!authz.ok) {
    return res.status(403).json({
      success: false,
      message:
        "Invalid recovery credentials. Use your account security PIN or PARENT_RECOVERY_KEY.",
    });
  }

  const targetSelf =
    req.body?.target_self === true ||
    req.body?.targetSelf === true ||
    String(req.body?.target || "").toLowerCase() === "self";
  const targetId = Number(req.body?.target_device_id ?? req.body?.targetDeviceId);
  const targetModel = String(req.body?.target_device_model ?? req.body?.targetDeviceModel ?? "").trim();
  let targetHw = String(req.body?.target_hardware_id ?? req.body?.targetHardwareId ?? "").trim();
  if (targetSelf) {
    targetHw = parentHardwareFrom(req);
    if (!targetHw) {
      return res.status(400).json({
        success: false,
        message: "target_self requires X-Device-Id header (open app on the phone that should be parent)",
      });
    }
  }

  if (!Number.isFinite(targetId) && !targetModel && !targetHw) {
    return res.status(400).json({
      success: false,
      message:
        "Provide target_self: true, target_device_id, target_device_model, or target_hardware_id",
    });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    let targetRow = null;
    if (Number.isFinite(targetId) && targetId > 0) {
      const [rows] = await conn.query(
        `SELECT id, status, device_model, device_id, device_name FROM devices WHERE user_id = ? AND id = ? LIMIT 1 FOR UPDATE`,
        [req.userId, targetId]
      );
      targetRow = rows[0] || null;
    } else if (targetHw) {
      const [rows] = await conn.query(
        `SELECT id, status, device_model, device_id, device_name FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1 FOR UPDATE`,
        [req.userId, targetHw]
      );
      targetRow = rows[0] || null;
      if (!targetRow) {
        const deviceName = String(req.body?.deviceName || req.body?.device_name || "My Phone").trim();
        const deviceModel = String(req.body?.deviceModel || req.body?.device_model || "").trim();
        await registerOrUpdateDevice(pool, io, {
          userId: req.userId,
          deviceId: targetHw,
          deviceName: deviceName || "My Phone",
          deviceModel,
        });
        const [again] = await conn.query(
          `SELECT id, status, device_model, device_id, device_name FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1 FOR UPDATE`,
          [req.userId, targetHw]
        );
        targetRow = again[0] || null;
      }
    } else {
      const like = `%${targetModel}%`;
      const [rows] = await conn.query(
        `SELECT id, status, device_model, device_id, device_name FROM devices
         WHERE user_id = ? AND (
           device_model LIKE ? OR device_name LIKE ? OR custom_name LIKE ?
         )
         ORDER BY id DESC
         LIMIT 1 FOR UPDATE`,
        [req.userId, like, like, like]
      );
      targetRow = rows[0] || null;
    }

    if (!targetRow) {
      const [all] = await conn.query(
        `SELECT id, device_model, device_name, device_id, status, is_parent FROM devices WHERE user_id = ? ORDER BY id DESC`,
        [req.userId]
      );
      await conn.rollback();
      return res.status(404).json({
        success: false,
        message:
          "Target device not found. Open recovery on the parent phone (target_self) or check model name in the list below.",
        devices: all.map((r) => ({
          id: r.id,
          device_model: r.device_model,
          device_name: r.device_name,
          device_id: r.device_id,
          status: r.status,
          is_parent: r.is_parent,
        })),
      });
    }
    if (String(targetRow.status) !== "active") {
      await conn.rollback();
      return res.status(400).json({
        success: false,
        message: "Target device must be active (approve it first if pending)",
      });
    }

    await conn.query(`UPDATE devices SET is_parent = 0 WHERE user_id = ?`, [req.userId]);
    await conn.query(`UPDATE devices SET is_parent = 1 WHERE user_id = ? AND id = ?`, [
      req.userId,
      targetRow.id,
    ]);
    await conn.commit();

    emitParentRoleChanged(io, req.userId);

    const devices = await fetchDevicesForUser(pool, req.userId);
    return res.json({
      success: true,
      message: "Parent role reassigned",
      parentDeviceId: targetRow.id,
      devices,
    });
  } catch (e) {
    try {
      await conn.rollback();
    } catch (_) {}
    console.error("[reassign-parent-recovery]", e);
    return res.status(500).json({ success: false, message: "Server error" });
  } finally {
    conn.release();
  }
}

/**
 * POST /api/update-device-name
 * Body: { device_id: <numeric devices.id>, new_name: string }
 */
async function postUpdateDeviceName(pool, req, res) {
  const rawId = req.body?.device_id ?? req.body?.id;
  const id = Number(rawId);
  if (!rawId || !Number.isFinite(id) || id <= 0) {
    return res.status(400).json({ success: false, message: "device_id required" });
  }
  const newName = req.body?.new_name != null ? String(req.body.new_name) : "";
  const customName = newName.trim() === "" ? null : newName.trim().slice(0, 255);

  try {
    const [r] = await pool.query(
      `UPDATE devices SET custom_name = ?, updated_at = CURRENT_TIMESTAMP
       WHERE id = ? AND user_id = ?`,
      [customName, id, req.userId]
    );
    if (r.affectedRows === 0) {
      return res.status(404).json({ success: false, message: "Device not found" });
    }
    const [rows] = await pool.query(`SELECT * FROM devices WHERE id = ? AND user_id = ? LIMIT 1`, [
      id,
      req.userId,
    ]);
    return res.json({ success: true, device: rowToDeviceJson(rows[0]) });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
}

/** Always returns a JSON array (never null/undefined) for Flutter list parsing. */
async function fetchDevicesForUser(pool, userId) {
  const [rows] = await pool.query(
    `SELECT * FROM devices WHERE user_id = ? ORDER BY is_parent DESC, id DESC`,
    [userId]
  );
  const list = Array.isArray(rows) ? rows : [];
  return list.map((row) => rowToDeviceJson(row)).filter(Boolean);
}

async function handleGetDevices(pool, req, res) {
  try {
    const devices = await fetchDevicesForUser(pool, req.userId);
    return res.json({ success: true, devices });
  } catch (e) {
    console.error("[GET devices]", e);
    return res.status(500).json({ success: false, message: "Server error", devices: [] });
  }
}

/** Session policy for the calling handset (X-Device-Id). */
async function handleDeviceAccess(pool, req, res) {
  const hw = parentHardwareFrom(req);
  if (!hw) {
    return res.json({
      success: true,
      registered: false,
      requiresApproval: false,
      requiresSecurityPin: false,
      isParent: false,
      message: "No device id on request",
    });
  }
  try {
    const [rows] = await pool.query(
      `SELECT * FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
      [req.userId, hw]
    );
    if (!rows.length) {
      return res.json({
        success: true,
        registered: false,
        requiresApproval: false,
        requiresSecurityPin: false,
        isParent: false,
      });
    }
    const device = rowToDeviceJson(rows[0]);
    const requiresApproval = String(rows[0].status) === "pending";
    const requiresSecurityPin = deviceNeedsSecurityPin(device, requiresApproval);
    return res.json({
      success: true,
      registered: true,
      device,
      requiresApproval,
      requiresSecurityPin,
      isParent: Boolean(device.is_parent || device.isParent),
    });
  } catch (e) {
    console.error("[GET /api/auth/device-access]", e);
    return res.status(500).json({ success: false, message: "Server error" });
  }
}

function registerDeviceRoutes(app, pool, authMiddleware, io = null) {
  const getDevicesHandler = (req, res) => handleGetDevices(pool, req, res);

  app.get("/api/auth/device-access", authMiddleware, (req, res) =>
    handleDeviceAccess(pool, req, res)
  );

  app.get("/api/devices", authMiddleware, getDevicesHandler);
  app.get("/api/get-devices", authMiddleware, getDevicesHandler);
  app.get("/get-devices", authMiddleware, getDevicesHandler);

  app.get("/api/devices/self", authMiddleware, async (req, res) => {
    const deviceId = String(req.query?.deviceId || req.query?.device_id || "").trim();
    if (!deviceId) {
      return res.status(400).json({ success: false, message: "deviceId query required" });
    }
    try {
      const [rows] = await pool.query(
        `SELECT * FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
        [req.userId, deviceId]
      );
      if (!rows.length) {
        return res.status(404).json({ success: false, message: "Device not registered" });
      }
      return res.json({ success: true, device: rowToDeviceJson(rows[0]) });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  /** Presence + optional battery for the calling device (`X-Device-Id`). */
  app.post("/api/devices/self/heartbeat", authMiddleware, async (req, res) => {
    const deviceId = parentHardwareFrom(req);
    if (!deviceId) {
      return res
        .status(400)
        .json({ success: false, message: "X-Device-Id header or deviceId body required" });
    }
    const raw = req.body?.batteryPercent ?? req.body?.battery;
    let bat = null;
    if (raw != null && raw !== "") {
      const n = Number(raw);
      if (Number.isFinite(n)) bat = Math.max(0, Math.min(100, Math.round(n)));
    }
    try {
      if (bat != null) {
        await pool.query(
          `UPDATE devices SET last_seen_at = CURRENT_TIMESTAMP, last_battery_percent = ?, updated_at = CURRENT_TIMESTAMP
           WHERE user_id = ? AND device_id = ?`,
          [bat, req.userId, deviceId]
        );
      } else {
        await pool.query(
          `UPDATE devices SET last_seen_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
           WHERE user_id = ? AND device_id = ?`,
          [req.userId, deviceId]
        );
      }
      return res.json({ success: true });
    } catch (e) {
      console.error("[POST /api/devices/self/heartbeat]", e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  app.post("/api/devices", authMiddleware, async (req, res) => {
    const deviceId = String(req.body?.deviceId || req.body?.device_id || "").trim();
    const deviceName = String(req.body?.deviceName || req.body?.device_name || "My Phone").trim() || "My Phone";
    const deviceModel = String(req.body?.deviceModel || req.body?.device_model || "").trim();
    if (!deviceId) {
      return res.status(400).json({ success: false, message: "deviceId required" });
    }
    try {
      const result = await registerOrUpdateDevice(pool, io, {
        userId: req.userId,
        deviceId,
        deviceName,
        deviceModel,
      });
      return res.json({
        success: true,
        device: result.device,
        requiresApproval: result.requiresApproval,
      });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  app.post("/api/devices/reassign-parent", authMiddleware, (req, res) =>
    reassignParentWithRecoveryKey(pool, io, req, res)
  );

  app.post("/api/devices/transfer-parent", authMiddleware, async (req, res) => {
    const parentHw = parentHardwareFrom(req);
    const targetId = Number(req.body?.target_device_id ?? req.body?.targetDeviceId);
    if (!parentHw) {
      return res.status(400).json({ success: false, message: "deviceId (parent hardware) required" });
    }
    if (!Number.isFinite(targetId) || targetId <= 0) {
      return res.status(400).json({ success: false, message: "target_device_id required" });
    }
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [parents] = await conn.query(
        `SELECT id FROM devices WHERE user_id = ? AND device_id = ? AND is_parent = 1 LIMIT 1 FOR UPDATE`,
        [req.userId, parentHw]
      );
      if (!parents.length) {
        await conn.rollback();
        return res.status(403).json({ success: false, message: "Only the parent device can transfer authority" });
      }
      const [targets] = await conn.query(
        `SELECT id, status FROM devices WHERE user_id = ? AND id = ? LIMIT 1 FOR UPDATE`,
        [req.userId, targetId]
      );
      if (!targets.length || String(targets[0].status) !== "active") {
        await conn.rollback();
        return res.status(400).json({ success: false, message: "Target must be an active device on this account" });
      }
      await conn.query(`UPDATE devices SET is_parent = 0 WHERE user_id = ?`, [req.userId]);
      await conn.query(`UPDATE devices SET is_parent = 1 WHERE user_id = ? AND id = ?`, [req.userId, targetId]);
      await conn.commit();

      emitParentRoleChanged(io, req.userId);

      const [rows] = await pool.query(`SELECT * FROM devices WHERE user_id = ? ORDER BY id DESC`, [
        req.userId,
      ]);
      return res.json({ success: true, devices: rows.map(rowToDeviceJson) });
    } catch (e) {
      try {
        await conn.rollback();
      } catch (_) {}
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    } finally {
      conn.release();
    }
  });

  app.post("/api/devices/:id/approve", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    try {
      const authz = await authorizeDeviceManagerAction(pool, req);
      if (!authz.ok) {
        return res.status(authz.status || 403).json({
          success: false,
          message: authz.message,
          requiresPin: authz.requiresPin === true,
        });
      }
      const [pending] = await pool.query(
        `SELECT * FROM devices WHERE user_id = ? AND id = ? AND status = 'pending' LIMIT 1`,
        [req.userId, id]
      );
      if (!pending.length) {
        return res.status(404).json({ success: false, message: "Pending device not found" });
      }
      await pool.query(
        `UPDATE devices SET status = 'active', updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?`,
        [id, req.userId]
      );
      const [rows] = await pool.query(`SELECT * FROM devices WHERE id = ? AND user_id = ? LIMIT 1`, [
        id,
        req.userId,
      ]);
      const json = rowToDeviceJson(rows[0]);
      emitDeviceActivated(io, id, json);
      return res.json({ success: true, device: json });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  app.post("/api/devices/:id/reject", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    try {
      const authz = await authorizeDeviceManagerAction(pool, req);
      if (!authz.ok) {
        return res.status(authz.status || 403).json({
          success: false,
          message: authz.message,
          requiresPin: authz.requiresPin === true,
        });
      }
      const [pending] = await pool.query(
        `SELECT id FROM devices WHERE user_id = ? AND id = ? AND status = 'pending' LIMIT 1`,
        [req.userId, id]
      );
      if (!pending.length) {
        return res.status(404).json({ success: false, message: "Pending device not found" });
      }
      emitDeviceRejected(io, id, { deviceId: id });
      await pool.query(`DELETE FROM devices WHERE id = ? AND user_id = ?`, [id, req.userId]);
      return res.json({ success: true });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  const renameHandler = (req, res) => postUpdateDeviceName(pool, req, res);
  app.post("/api/update-device-name", authMiddleware, renameHandler);
  app.post("/api/rename-device", authMiddleware, renameHandler);
  app.post("/rename-device", authMiddleware, renameHandler);

  app.put("/api/devices/:id", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    const name = String(req.body?.deviceName || req.body?.device_name || "").trim();
    if (!name) {
      return res.status(400).json({ success: false, message: "deviceName required" });
    }
    try {
      const [r] = await pool.query(
        `UPDATE devices SET custom_name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?`,
        [name.slice(0, 255), id, req.userId]
      );
      if (r.affectedRows === 0) {
        return res.status(404).json({ success: false, message: "Device not found" });
      }
      const [rows] = await pool.query(`SELECT * FROM devices WHERE id = ? AND user_id = ? LIMIT 1`, [
        id,
        req.userId,
      ]);
      return res.json({ success: true, device: rowToDeviceJson(rows[0]) });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  async function assertCanManageDeviceSettings(conn, userId, targetRow, req) {
    const callerHw = parentHardwareFrom(req);
    if (!callerHw) return true;
    const [callerRows] = await conn.query(
      `SELECT id, device_id, is_parent FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
      [userId, callerHw]
    );
    if (!callerRows.length) return true;
    const caller = callerRows[0];
    if (String(caller.device_id) === String(targetRow.device_id)) return true;
    if (!caller.is_parent) {
      const err = new Error("Only the parent device can change settings for other devices");
      err.status = 403;
      throw err;
    }
    return true;
  }

  app.get("/api/devices/:id/settings", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    try {
      const [rows] = await pool.query(`SELECT * FROM devices WHERE id = ? AND user_id = ? LIMIT 1`, [
        id,
        req.userId,
      ]);
      if (!rows.length) {
        return res.status(404).json({ success: false, message: "Device not found" });
      }
      const parsed = parseSimSettingsRow(rows[0]);
      return res.json({
        success: true,
        child_device_id: rows[0].device_id,
        config: simSettingsToApi(parsed),
        device: rowToDeviceJson(rows[0]),
      });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

  app.put("/api/devices/:id/settings", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    const { parsed, json, smsFilterEnabled, allowedKeywords, blockedKeywords } =
      bodyToSimSettings(req.body);

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [targets] = await conn.query(
        `SELECT * FROM devices WHERE id = ? AND user_id = ? LIMIT 1 FOR UPDATE`,
        [id, req.userId]
      );
      if (!targets.length) {
        await conn.rollback();
        return res.status(404).json({ success: false, message: "Device not found" });
      }
      try {
        await assertCanManageDeviceSettings(conn, req.userId, targets[0], req);
      } catch (e) {
        await conn.rollback();
        return res.status(e.status || 403).json({ success: false, message: e.message });
      }
      await conn.query(
        `UPDATE devices SET
           sim_settings = CAST(? AS JSON),
           sms_filter_enabled = ?,
           allowed_keywords = ?,
           blocked_keywords = ?,
           updated_at = CURRENT_TIMESTAMP
         WHERE id = ? AND user_id = ?`,
        [json, smsFilterEnabled, allowedKeywords, blockedKeywords, id, req.userId]
      );
      await conn.commit();
      const [rows] = await pool.query(`SELECT * FROM devices WHERE id = ? AND user_id = ? LIMIT 1`, [
        id,
        req.userId,
      ]);
      return res.json({
        success: true,
        config: simSettingsToApi(parsed),
        device: rowToDeviceJson(rows[0]),
      });
    } catch (e) {
      try {
        await conn.rollback();
      } catch (_) {}
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    } finally {
      conn.release();
    }
  });

  app.delete("/api/devices/:id", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    try {
      const [r] = await pool.query(`DELETE FROM devices WHERE id = ? AND user_id = ?`, [id, req.userId]);
      if (r.affectedRows === 0) {
        return res.status(404).json({ success: false, message: "Device not found" });
      }
      return res.json({ success: true });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });
}

module.exports = {
  registerDeviceRoutes,
  rowToDeviceJson,
  postUpdateDeviceName,
  fetchDevicesForUser,
};
