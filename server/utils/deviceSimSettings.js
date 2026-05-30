"use strict";

/**
 * Per-child SIM remote config stored in `devices.sim_settings` (JSON).
 *
 * Canonical shape:
 * {
 *   "sim1": { "active": true, "allowed_senders": ["bKash", "NAGAD"] },
 *   "sim2": { "active": false, "allowed_senders": ["GovInfo"] }
 * }
 */

function splitKeywords(csv) {
  if (!csv || String(csv).trim() === "") return [];
  return String(csv)
    .split(",")
    .map((k) => k.trim())
    .filter(Boolean);
}

function normalizeSimSlot(raw, fallbackActive) {
  const m = raw && typeof raw === "object" ? raw : {};
  const active =
    m.active === true ||
    m.isEnabled === true ||
    m.status === "on" ||
    (fallbackActive && m.active !== false && m.status !== "off");
  const allowed_senders = Array.isArray(m.allowed_senders)
    ? m.allowed_senders.map((x) => String(x).trim()).filter(Boolean)
    : Array.isArray(m.filters)
      ? m.filters.map((x) => String(x).trim()).filter(Boolean)
      : [];
  return { active, allowed_senders };
}

function legacyFromRow(row) {
  const smsOn = Boolean(row.sms_filter_enabled);
  return {
    sim1: {
      active: smsOn,
      allowed_senders: splitKeywords(row.allowed_keywords),
    },
    sim2: {
      active: smsOn,
      allowed_senders: splitKeywords(row.blocked_keywords),
    },
  };
}

function parseSimSettingsRow(row) {
  if (!row) {
    return {
      sim1: { active: true, allowed_senders: [] },
      sim2: { active: true, allowed_senders: [] },
      bank_accounts: [],
    };
  }
  const raw = row.sim_settings;
  if (raw != null && raw !== "") {
    try {
      const obj = typeof raw === "string" ? JSON.parse(raw) : raw;
      if (obj && typeof obj === "object") {
        const smsOn = Boolean(row.sms_filter_enabled);
        return {
          sim1: normalizeSimSlot(obj.sim1, smsOn),
          sim2: normalizeSimSlot(obj.sim2, smsOn),
          bank_accounts: obj.bank_accounts || obj.bankAccounts || [],
        };
      }
    } catch {
      /* fall through to legacy */
    }
  }
  const leg = legacyFromRow(row);
  return {
    ...leg,
    bank_accounts: [],
  };
}

function simSettingsToApi(parsed) {
  const p = parsed || parseSimSettingsRow(null);
  const slot = (key) => ({
    active: p[key].active,
    status: p[key].active ? "on" : "off",
    allowed_senders: p[key].allowed_senders,
    filters: p[key].allowed_senders,
  });
  return {
    sim1: slot("sim1"),
    sim2: slot("sim2"),
    bank_accounts: p.bank_accounts || [],
  };
}

/** Build DB JSON + legacy keyword columns from PUT body. */
function bodyToSimSettings(body) {
  const sim1 = body?.sim1 || {};
  const sim2 = body?.sim2 || {};
  const sim1On = sim1.active === true || sim1.status === "on" || sim1.isEnabled === true;
  const sim2On = sim2.active === true || sim2.status === "on" || sim2.isEnabled === true;
  const f1 = Array.isArray(sim1.allowed_senders)
    ? sim1.allowed_senders
    : Array.isArray(sim1.filters)
      ? sim1.filters
      : [];
  const f2 = Array.isArray(sim2.allowed_senders)
    ? sim2.allowed_senders
    : Array.isArray(sim2.filters)
      ? sim2.filters
      : [];
  const sim1Number = body?.sim1_number || body?.sim1Number || null;
  const sim2Number = body?.sim2_number || body?.sim2Number || null;
  const bankAccounts = body?.bank_accounts || body?.bankAccounts || [];

  const parsed = {
    sim1: {
      active: sim1On,
      allowed_senders: f1.map((x) => String(x).trim()).filter(Boolean),
    },
    sim2: {
      active: sim2On,
      allowed_senders: f2.map((x) => String(x).trim()).filter(Boolean),
    },
    bank_accounts: bankAccounts,
  };
  return {
    parsed,
    json: JSON.stringify(parsed),
    smsFilterEnabled: sim1On || sim2On ? 1 : 0,
    allowedKeywords: parsed.sim1.allowed_senders.join(","),
    blockedKeywords: parsed.sim2.allowed_senders.join(","),
    sim1Number,
    sim2Number,
  };
}

module.exports = {
  parseSimSettingsRow,
  simSettingsToApi,
  bodyToSimSettings,
};
