"use strict";

const { parseSimSettingsRow, simSettingsToApi } = require("./deviceSimSettings");

function safeIsoDate(v) {
  if (v == null || v === "") return null;
  try {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  } catch {
    return null;
  }
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
  const lastSeenIso = safeIsoDate(row.last_seen_at);
  const simParsed = parseSimSettingsRow(row);
  const simSettings = simSettingsToApi(simParsed);
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
    sim_settings: simSettings,
    simSettings,
    child_device_id: row.device_id,
    childDeviceId: row.device_id,
    sim_1_active: simParsed.sim1.active,
    sim1Active: simParsed.sim1.active,
    sim_1_allowed_senders: simParsed.sim1.allowed_senders,
    sim1AllowedSenders: simParsed.sim1.allowed_senders,
    sim_2_active: simParsed.sim2.active,
    sim2Active: simParsed.sim2.active,
    sim_2_allowed_senders: simParsed.sim2.allowed_senders,
    sim2AllowedSenders: simParsed.sim2.allowed_senders,
    display_name: display,
    displayName: display,
    created_at: row.created_at,
    createdAt: row.created_at,
    updated_at: row.updated_at,
    updatedAt: row.updated_at,
    last_seen_at: lastSeenIso,
    lastSeenAt: lastSeenIso,
    last_battery_percent:
      row.last_battery_percent != null ? Number(row.last_battery_percent) : null,
    lastBatteryPercent:
      row.last_battery_percent != null ? Number(row.last_battery_percent) : null,
  };
}

module.exports = { rowToDeviceJson };
