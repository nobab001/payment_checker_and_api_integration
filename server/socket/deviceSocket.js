"use strict";

const jwt = require("jsonwebtoken");

/**
 * Socket.io: user rooms `user:<userId>`, per-device `device:<rowId>`.
 * Auth: handshake.auth.token (JWT) + handshake.auth.deviceId (hardware id).
 */

function registerDeviceSocket(io, pool, jwtSecret) {
  io.use((socket, next) => {
    const raw =
      socket.handshake.auth?.token ||
      String(socket.handshake.headers?.authorization || "").replace(/^Bearer\s+/i, "");
    const token = typeof raw === "string" ? raw.trim() : "";
    if (!token) {
      return next(new Error("Unauthorized"));
    }
    try {
      const payload = jwt.verify(token, jwtSecret);
      const userId = Number(payload.sub);
      if (!userId) {
        return next(new Error("Unauthorized"));
      }
      socket.userId = userId;
      socket.hardwareDeviceId = String(socket.handshake.auth?.deviceId || "").trim();
      next();
    } catch (_) {
      next(new Error("Unauthorized"));
    }
  });

  io.on("connection", async (socket) => {
    const userId = socket.userId;
    const hwId = socket.hardwareDeviceId;
    socket.join(`user:${userId}`);
    socket.data.isParent = false;
    socket.data.deviceRowId = null;

    if (hwId) {
      try {
        const [rows] = await pool.query(
          `SELECT id, status, is_parent FROM devices WHERE user_id = ? AND device_id = ? LIMIT 1`,
          [userId, hwId]
        );
        if (rows.length) {
          socket.data.deviceRowId = rows[0].id;
          socket.data.isParent = Boolean(rows[0].is_parent);
          socket.join(`device:${rows[0].id}`);
        }
      } catch (e) {
        console.error("[socket] device lookup failed", e);
      }
    }
  });
}

/** Notify only sockets marked as parent (see connection handler). */
async function emitApprovalRequestToParents(io, userId, deviceJson) {
  if (!io) return;
  try {
    const sockets = await io.in(`user:${userId}`).fetchSockets();
    for (const s of sockets) {
      if (s.data.isParent) {
        s.emit("device:approval_request", { device: deviceJson });
      }
    }
  } catch (e) {
    console.error("[socket] emitApprovalRequestToParents", e);
  }
}

function emitDeviceActivated(io, deviceRowId, deviceJson) {
  if (!io) return;
  io.to(`device:${deviceRowId}`).emit("device:activated", { device: deviceJson });
}

function emitDeviceRejected(io, deviceRowId, payload = {}) {
  if (!io) return;
  io.to(`device:${deviceRowId}`).emit("device:rejected", payload);
}

/** After parent transfer, all account devices should refresh local parent flags. */
function emitParentRoleChanged(io, userId) {
  if (!io) return;
  io.to(`user:${userId}`).emit("device:parent_role_changed", {});
}

module.exports = {
  registerDeviceSocket,
  emitApprovalRequestToParents,
  emitDeviceActivated,
  emitDeviceRejected,
  emitParentRoleChanged,
};
