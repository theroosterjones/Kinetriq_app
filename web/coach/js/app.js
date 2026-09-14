/**
 * Boot and routing.
 *
 * Hash routing, because this is a static folder that can be dropped on any host
 * without a rewrite rule. `#/` is the roster and `#/client/<uuid>` is one client, so a
 * coach can bookmark or reopen a client directly.
 */

import { el, render, card, banner } from "./dom.js";
import { isConfigured } from "./config.js";
import * as api from "./api.js";
import * as coachData from "./coach.js";
import { renderLogin } from "./views/login.js";
import { renderRoster } from "./views/roster.js";
import { renderClient } from "./views/client.js";

const root = document.getElementById("root");

/**
 * Roster rows keyed by client id, populated when a client is opened from the list, so
 * the client view can render immediately. A deep link or a reload finds it empty and
 * fetches the roster to resolve the id.
 */
let clientsByID = new Map();
let pendingNotice = null;

function setupNeeded() {
  render(root, [
    el("div", { className: "auth" }, [
      el("h1", { className: "auth__brand", text: "Kinetriq for Coaches" }),
      card([
        el("p", { className: "card__title", text: "Not configured yet" }),
        el("p", { className: "muted", text: "Copy web/coach/config.example.js to web/coach/config.js and fill in your Supabase project URL and anon key, then reload. See web/coach/README.md for deployment." }),
      ]),
    ]),
  ]);
}

function showLogin(notice) {
  renderLogin(root, {
    notice,
    onSignedIn: () => {
      clientsByID = new Map();
      navigate("#/");
    },
  });
}

async function showRoster() {
  renderRoster(root, {
    onOpenClient: (client) => {
      clientsByID.set(client.clientUserID, client);
      navigate(`#/client/${client.clientUserID}`);
    },
  });
}

async function showClient(clientUserID) {
  let client = clientsByID.get(clientUserID);

  if (!client) {
    // Deep link or a reload. Fetch the roster to resolve the id, which also confirms
    // the link is still active — the RLS policy stops granting access the moment it
    // isn't, and a stale bookmark should say so rather than render an empty shell.
    render(root, [el("div", { className: "page" }, [card([el("p", { className: "muted", text: "Loading client…" })])])]);
    try {
      const clients = await coachData.fetchRoster();
      clientsByID = new Map(clients.map((entry) => [entry.clientUserID, entry]));
      client = clientsByID.get(clientUserID);
    } catch (error) {
      const { message, code } = api.userFacingMessage(error);
      render(root, [
        el("div", { className: "page" }, [banner("error", "Couldn't load that client", message, code)]),
      ]);
      return;
    }
  }

  if (!client) {
    render(root, [
      el("div", { className: "page" }, [
        banner("warning", "That client isn't on your roster", "The link may have ended, or the bookmark points at someone else's client."),
        card([el("a", { attrs: { href: "#/" }, text: "Back to your roster" })]),
      ]),
    ]);
    return;
  }

  renderClient(root, client, {
    onBack: (options) => {
      if (options?.reload) clientsByID = new Map();
      navigate("#/");
    },
  });
}

function navigate(hash) {
  if (location.hash === hash) route();
  else location.hash = hash;
}

function route() {
  if (!isConfigured) return setupNeeded();

  if (!api.isAuthenticated()) {
    const notice = pendingNotice;
    pendingNotice = null;
    return showLogin(notice);
  }

  const match = /^#\/client\/([0-9a-fA-F-]{36})$/.exec(location.hash);
  if (match) return showClient(match[1]);
  return showRoster();
}

async function boot() {
  if (!isConfigured) return setupNeeded();

  // A magic-link redirect arrives with tokens in the fragment. Consume them before
  // routing, or the router sees "not signed in" and bounces straight back to login.
  const captured = await api.captureSessionFromURL();
  if (captured.status === "error") {
    pendingNotice = { kind: "error", title: "That link didn't work", message: captured.message, code: "AUTH-LINK" };
  }

  try {
    await api.bootstrapSession();
  } catch {
    // Offline or a 5xx: keep whatever session we have and let the first real request
    // surface the problem. Signing a coach out because the network blipped is worse.
  }

  api.onSessionChange((session) => {
    if (!session) {
      clientsByID = new Map();
      pendingNotice = {
        kind: "warning",
        title: "Signed out",
        message: "Sign in again to get back to your roster.",
        code: "AUTH-SIGNEDOUT",
      };
      navigate("#/");
    }
  });

  window.addEventListener("hashchange", route);
  route();
}

boot().catch((error) => {
  render(root, [
    el("div", { className: "page" }, [
      banner("error", "Kinetriq couldn't start", String(error?.message || error), "APP-BOOT"),
    ]),
  ]);
});
