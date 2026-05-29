"use strict";

/**
 * Hybrid device authorization:
 * - Parent handset: no security PIN for approve / login
 * - Pending child: no PIN until parent approves
 * - Active non-parent: security PIN required on login / session
 */
function deviceNeedsSecurityPin(device, requiresApproval) {
  if (!device) return false;
  if (requiresApproval) return false;

  const status = String(device.status || "active").toLowerCase();
  if (status === "pending") return false;

  const isParent =
    device.is_parent === true ||
    device.is_parent === 1 ||
    device.isParent === true ||
    device.isParent === 1;
  if (isParent) return false;

  return status === "active";
}

module.exports = { deviceNeedsSecurityPin };
