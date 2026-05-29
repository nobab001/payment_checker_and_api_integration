"use strict";

const crypto = require("crypto");
const { getMerchantByApiKeyId } = require("../services/merchantService");

function hashSecret(plain) {
  return crypto.createHash("sha256").update(String(plain)).digest("hex");
}

/** Merchant API: X-Api-Key + X-Api-Secret (secret stored as SHA-256 hash in DB). */
async function merchantApiAuth(req, res, next) {
  const apiKey = req.headers["x-api-key"] || req.headers["x-api-key-id"];
  const apiSecret = req.headers["x-api-secret"];
  if (!apiKey || !apiSecret) {
    return res.status(401).json({
      success: false,
      message: "X-Api-Key and X-Api-Secret required",
    });
  }

  const merchant = await getMerchantByApiKeyId(String(apiKey).trim());
  if (!merchant) {
    return res.status(401).json({ success: false, message: "Invalid API credentials" });
  }

  const providedHash = hashSecret(apiSecret);
  if (providedHash !== merchant.api_secret_hash) {
    return res.status(401).json({ success: false, message: "Invalid API credentials" });
  }

  req.merchant = merchant;
  req.accountId = merchant.account_id;
  next();
}

function captureRawBody(req, res, buf) {
  if (buf?.length) req.rawBody = buf.toString("utf8");
}

module.exports = { merchantApiAuth, captureRawBody, hashSecret };
