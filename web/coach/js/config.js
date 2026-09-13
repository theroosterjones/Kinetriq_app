/**
 * Deploy-time configuration, read from `config.js` (see config.example.js).
 *
 * Kept out of the module graph on purpose: `config.js` is gitignored and loaded as a
 * classic script from index.html, so a checkout without it still boots and can show
 * setup instructions rather than throwing a module-resolution error at a blank page.
 */

const raw = globalThis.KINETRIQ_CONFIG || {};

export const config = {
  // Trailing slash trimmed so every call site can append "auth/v1/..." safely.
  supabaseUrl: String(raw.supabaseUrl || "").trim().replace(/\/+$/, ""),
  supabaseAnonKey: String(raw.supabaseAnonKey || "").trim(),
  appStoreURL: String(raw.appStoreURL || "").trim(),
};

const placeholder = /YOUR-(PROJECT-REF|ANON-KEY)/i;

export const isConfigured =
  config.supabaseUrl.startsWith("https://") &&
  config.supabaseAnonKey.length > 20 &&
  !placeholder.test(config.supabaseUrl) &&
  !placeholder.test(config.supabaseAnonKey);
