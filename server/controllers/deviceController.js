"use strict";

/**
 * Device CRUD, parent/child approval (`status`, `is_parent`), rename (`custom_name`).
 */

const {
  emitApprovalRequestToParents,
  emitDeviceActivated,
  emitDeviceRejected,
  emitParentRoleChanged,
} = require("../socket/deviceSocket");

function parentHardwareFrom(req) {
  return String(req.headers["x-device-id"] || req.body?.deviceId || "").trim();
}

function rowToDeviceJson(row) {
  if (!row) return null;
  const custom = row.custom_name != null ? String(row.custom_name) : "";
  const model = row.device_model != null ? String(row.device_model) : "";
  const name = row.device_name != null ? String(row.device_name) : "";
  const display =
    custom.trim() !== ""
      ? custom.trim()
      : model.trim() !== ""
        ? model.trim()
        : name || "Device";
  const status = row.status != null ? String(row.status) : "active";
  const isParent = Boolean(row.is_parent);
  return {
    id: row.id,
    userId: row.user_id,
    device_id: row.device_id,
    deviceId: row.device_id,
    device_name: name,
    deviceName: name,
    custom_name: custom,
    customName: custom,
    status,
    is_parent: isParent,
    isParent,
    device_model: model,
    deviceModel: model,
    android_version: row.android_version != null ? String(row.android_version) : "",
    androidVersion: row.android_version != null ? String(row.android_version) : "",
    sim1_number: row.sim1_number,
    sim1Number: row.sim1_number,
    sim1_operator: row.sim1_operator,
    sim1Operator: row.sim1_operator,
    sim2_number: row.sim2_number,
    sim2Number: row.sim2_number,
    sim2_operator: row.sim2_operator,
    sim2Operator: row.sim2_operator,
    sms_filter_enabled: Boolean(row.sms_filter_enabled),
    smsFilterEnabled: Boolean(row.sms_filter_enabled),
    block_unknown: Boolean(row.block_unknown),
    blockUnknown: Boolean(row.block_unknown),
    block_incoming: Boolean(row.block_incoming),
    blockIncoming: Boolean(row.block_incoming),
    allowed_keywords: row.allowed_keywords != null ? String(row.allowed_keywords) : "",
    allowedKeywords: row.allowed_keywords != null ? String(row.allowed_keywords) : "",
    blocked_keywords: row.blocked_keywords != null ? String(row.blocked_keywords) : "",
    blockedKeywords: row.blocked_keywords != null ? String(row.blocked_keywords) : "",
    display_name: display,
    displayName: display,
    created_at: row.created_at,
    createdAt: row.created_at,
    updated_at: row.updated_at,
    updatedAt: row.updated_at,
  };
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

function registerDeviceRoutes(app, pool, authMiddleware, io = null) {
  app.get("/api/devices", authMiddleware, async (req, res) => {
    try {
      const [rows] = await pool.query(
        `SELECT * FROM devices WHERE user_id = ? ORDER BY updated_at DESC`,
        [req.userId]
      );
      return res.json({
        success: true,
        devices: rows.map(rowToDeviceJson),
      });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

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

  app.post("/api/devices", authMiddleware, async (req, res) => {
    const deviceId = String(req.body?.deviceId || req.body?.device_id || "").trim();
    const deviceName = String(req.body?.deviceName || req.body?.device_name || "My Phone").trim() || "My Phone";
    const deviceModel = String(req.body?.deviceModel || req.body?.device_model || "").trim();
    if (!deviceId) {
      return res.status(400).json({ success: false, message: "deviceId required" });
    }
    try {
      const [[{ cnt }]] = await pool.query(`SELECT COUNT(*) AS cnt FROM devices WHERE user_id = ?`, [
        req.userId,
      ]);
      const isFirstAccountDevice = Number(cnt) === 0;

      const [existing] = await pool.query(
        `SELECT * FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
        [req.userId, deviceId]
      );

      if (existing.length) {
        await pool.query(
          `UPDATE devices SET
             device_name = ?,
             device_model = IF(? <> '', ?, device_model),
             updated_at = CURRENT_TIMESTAMP
           WHERE id = ?`,
          [deviceName, deviceModel, deviceModel, existing[0].id]
        );
      } else {
        const status = isFirstAccountDevice ? "active" : "pending";
        const isParent = isFirstAccountDevice ? 1 : 0;
        await pool.query(
          `INSERT INTO devices (user_id, device_id, device_name, device_model, status, is_parent)
           VALUES (?, ?, ?, ?, ?, ?)`,
          [req.userId, deviceId, deviceName, deviceModel, status, isParent]
        );
      }

      const [rows] = await pool.query(
        `SELECT * FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
        [req.userId, deviceId]
      );
      const row = rows[0];
      const json = rowToDeviceJson(row);

      if (io && String(row.status) === "pending" && !existing.length) {
        await emitApprovalRequestToParents(io, req.userId, json);
      }

      return res.json({ success: true, device: json });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ success: false, message: "Server error" });
    }
  });

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

      const [rows] = await pool.query(`SELECT * FROM devices WHERE user_id = ? ORDER BY updated_at DESC`, [
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
    const parentHw = parentHardwareFrom(req);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    if (!parentHw) {
      return res.status(400).json({ success: false, message: "deviceId (parent hardware) required" });
    }
    try {
      const [parents] = await pool.query(
        `SELECT id FROM devices WHERE user_id = ? AND device_id = ? AND is_parent = 1 LIMIT 1`,
        [req.userId, parentHw]
      );
      if (!parents.length) {
        return res.status(403).json({ success: false, message: "Only the parent device can approve" });
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
    const parentHw = parentHardwareFrom(req);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    if (!parentHw) {
      return res.status(400).json({ success: false, message: "deviceId (parent hardware) required" });
    }
    try {
      const [parents] = await pool.query(
        `SELECT id FROM devices WHERE user_id = ? AND device_id = ? AND is_parent = 1 LIMIT 1`,
        [req.userId, parentHw]
      );
      if (!parents.length) {
        return res.status(403).json({ success: false, message: "Only the parent device can reject" });
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

  app.post("/api/update-device-name", authMiddleware, (req, res) =>
    postUpdateDeviceName(pool, req, res)
  );

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

  app.put("/api/devices/:id/settings", authMiddleware, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: "invalid id" });
    }
    const sim1 = req.body?.sim1 || {};
    const sim2 = req.body?.sim2 || {};
    const sim1On = sim1.status === "on" || sim1.isEnabled === true;
    const sim2On = sim2.status === "on" || sim2.isEnabled === true;
    const f1 = Array.isArray(sim1.filters) ? sim1.filters.map((x) => String(x).trim()).filter(Boolean) : [];
    const f2 = Array.isArray(sim2.filters) ? sim2.filters.map((x) => String(x).trim()).filter(Boolean) : [];
    const smsFilter = sim1On || sim2On;
    const allowed = f1.join(",");
    const blocked = f2.join(",");

    try {
      const [r] = await pool.query(
        `UPDATE devices SET
           sms_filter_enabled = ?, allowed_keywords = ?, blocked_keywords = ?,
           updated_at = CURRENT_TIMESTAMP
         WHERE id = ? AND user_id = ?`,
        [smsFilter ? 1 : 0, allowed, blocked, id, req.userId]
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
};
