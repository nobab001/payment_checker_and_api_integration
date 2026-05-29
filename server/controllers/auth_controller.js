"use strict";

const { rowToDeviceJson } = require("../utils/deviceRowJson");

function hardwareFrom(req) {
  return String(
    req.headers["x-device-id"] ||
      req.query?.deviceId ||
      req.query?.device_id ||
      ""
  ).trim();
}

/**
 * VPS polling: child device checks approval state (no Firebase).
 * GET /api/check-device-status?deviceId=...
 * Returns status: pending | approved | rejected
 */
async function checkDeviceStatus(pool, req, res) {
  const deviceId = hardwareFrom(req);
  if (!deviceId) {
    return res.status(400).json({
      success: false,
      status: "unknown",
      message: "deviceId required",
    });
  }
  try {
    const [rows] = await pool.query(
      `SELECT * FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
      [req.userId, deviceId]
    );
    if (!rows.length) {
      return res.json({
        success: true,
        status: "rejected",
        message: "Device not registered or was rejected",
      });
    }
    const row = rows[0];
    const raw = String(row.status || "active");
    const status = raw === "active" ? "approved" : raw;
    return res.json({
      success: true,
      status,
      device: rowToDeviceJson(row),
    });
  } catch (e) {
    console.error("[check-device-status]", e);
    return res.status(500).json({
      success: false,
      status: "unknown",
      message: "Server error",
    });
  }
}

/**
 * Parent device: list pending child devices awaiting approval.
 * GET /api/get-pending-requests
 */
async function getPendingRequests(pool, req, res) {
  try {
    const [parents] = await pool.query(
      `SELECT id FROM devices WHERE user_id = ? AND is_parent = 1 LIMIT 1`,
      [req.userId]
    );
    if (!parents.length) {
      return res.status(403).json({
        success: false,
        message: "No parent device on this account",
        devices: [],
      });
    }
    const [rows] = await pool.query(
      `SELECT * FROM devices WHERE user_id = ? AND status = 'pending' ORDER BY id DESC`,
      [req.userId]
    );
    const devices = rows.map((r) => rowToDeviceJson(r)).filter(Boolean);
    return res.json({ success: true, devices });
  } catch (e) {
    console.error("[get-pending-requests]", e);
    return res.status(500).json({
      success: false,
      message: "Server error",
      devices: [],
    });
  }
}

function registerAuthDeviceRoutes(app, pool, authMiddleware) {
  app.get("/api/check-device-status", authMiddleware, (req, res) =>
    checkDeviceStatus(pool, req, res)
  );
  app.get("/api/get-pending-requests", authMiddleware, (req, res) =>
    getPendingRequests(pool, req, res)
  );
}

module.exports = {
  registerAuthDeviceRoutes,
  checkDeviceStatus,
  getPendingRequests,
};
