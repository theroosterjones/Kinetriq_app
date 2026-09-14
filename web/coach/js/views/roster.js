import { el, render, card, eyebrow, button, banner, pill, field, input } from "../dom.js";
import * as api from "../api.js";
import * as coachData from "../coach.js";
import {
  reasonFor, reasonLabel, needsAttention, attentionCount, daysSinceLastSession,
} from "../triage.js";
import { formatDate, relativeDays, pluralize, scoreTone } from "../format.js";

/**
 * The roster is a work queue, not a feed.
 *
 * Same premise as the phone: the useful question on a Tuesday morning is which of
 * forty clients to look at, and that is a question about measurements, which is the
 * one thing scheduling and billing platforms cannot answer. So the list leads with
 * triage and the ordering is `triage.js`, shared in spirit with `CoachTriage`.
 */
export function renderRoster(container, { onOpenClient } = {}) {
  const state = {
    loading: true,
    error: null,
    coach: null,
    clients: [],
    invites: [],
    invitePanelOpen: false,
    newCode: null,
    inviteError: null,
    inviteBusy: false,
  };

  async function load() {
    state.loading = true;
    draw();
    try {
      const [coachRecord, clients, invites] = await Promise.all([
        coachData.fetchCoachRecord(),
        coachData.fetchRoster(),
        coachData.fetchInvites(),
      ]);
      state.coach = coachRecord;
      state.clients = clients;
      state.invites = invites;
      state.error = null;
    } catch (error) {
      state.error = api.userFacingMessage(error);
    } finally {
      state.loading = false;
      draw();
    }
  }

  function draw() {
    render(container, [
      el("div", { className: "page" }, [
        topbar(),
        el("div", { className: "stack" }, contentSections()),
      ]),
    ]);
  }

  function topbar() {
    const session = api.currentSession();
    const limit = state.coach?.clientLimit;

    return el("header", { className: "topbar" }, [
      el("div", {}, [
        el("h1", { className: "topbar__title", text: "Clients" }),
        el("p", {
          className: "topbar__meta",
          text: session?.user?.email
            ? `Signed in as ${session.user.email}`
            : "Kinetriq coach dashboard",
        }),
      ]),
      el("div", { className: "topbar__spacer" }),
      el("div", { className: "topbar__actions" }, [
        limit
          ? pill(`${state.clients.length}/${limit} clients`)
          : null,
        button("Refresh", { variant: "btn--secondary btn--small", onClick: load, disabled: state.loading }),
        button("Sign out", {
          variant: "btn--secondary btn--small",
          onClick: async () => { await api.signOut(); },
        }),
      ]),
    ]);
  }

  function contentSections() {
    if (state.loading && state.clients.length === 0) {
      return [card([el("p", { className: "muted", text: "Loading your roster…" })])];
    }
    if (state.error) {
      return [
        banner("error", "Couldn't load your roster", state.error.message, state.error.code),
        card([button("Try again", { onClick: load })]),
      ];
    }
    if (!state.coach) {
      return [notACoachCard()];
    }

    return [
      state.coach.clientLimit === 0 ? lapsedBanner() : null,
      summaryCard(),
      invitePanel(),
      state.clients.length === 0 ? emptyRoster() : clientList(),
      openInvitesCard(),
      privacyNote(),
    ].filter(Boolean);
  }

  function notACoachCard() {
    return card([
      eyebrow("Not set up yet"),
      el("h2", { className: "card__title", text: "This account isn't a coach account" }),
      el("p", { className: "muted", text: "Coach plans are bought in the Kinetriq iOS app, under Settings → Kinetriq for Coaches. Once your plan is active, open the roster there once and this dashboard will show the same clients." }),
    ]);
  }

  function lapsedBanner() {
    return banner(
      "warning",
      "Coach plan isn't active",
      "You can still review the clients you already have, but you can't add new ones until the coach subscription is renewed in the App Store. Nobody has been unlinked.",
    );
  }

  function summaryCard() {
    const attention = attentionCount(state.clients);
    return card([
      eyebrow("Roster"),
      el("h2", {
        className: "card__title",
        text: state.clients.length === 0
          ? "No clients yet"
          : attention === 0
            ? "Everyone's on track"
            : `${attention} need${attention === 1 ? "s" : ""} a look`,
      }),
      el("p", {
        className: "muted",
        text: "Sorted by who needs attention first — clients who've gone quiet, whose consistency is falling, or who have a new asymmetry flag.",
      }),
    ]);
  }

  function invitePanel() {
    const canInvite = (state.coach?.clientLimit ?? 0) > 0;

    if (!state.invitePanelOpen) {
      return card([
        el("div", { className: "row" }, [
          el("div", {}, [
            el("p", { className: "card__title", text: "Add a client" }),
            el("p", { className: "muted", text: "Kinetriq gives you a short code. Your client enters it in the app under Settings → Connect with a Coach." }),
          ]),
          el("div", { className: "topbar__spacer" }),
          button("Create invite code", {
            disabled: !canInvite,
            onClick: () => { state.invitePanelOpen = true; state.newCode = null; state.inviteError = null; draw(); },
          }),
        ]),
      ]);
    }

    if (state.newCode) {
      return card([
        eyebrow("Invite created"),
        el("p", { className: "code-block", text: state.newCode }),
        el("p", { className: "muted", text: "Read it out or text it over. It works once and expires in 30 days." }),
        el("div", { className: "row" }, [
          button("Copy code", {
            variant: "btn--secondary",
            onClick: async (event) => {
              try {
                await navigator.clipboard.writeText(state.newCode);
                event.currentTarget.textContent = "Copied";
              } catch {
                event.currentTarget.textContent = "Select the code above to copy";
              }
            },
          }),
          button("Done", {
            variant: "btn--secondary",
            onClick: () => { state.invitePanelOpen = false; state.newCode = null; load(); },
          }),
        ]),
      ]);
    }

    const labelInput = input({
      name: "label",
      placeholder: "Jamie — knee rehab",
    });

    return card([
      eyebrow("Add a client"),
      el("form", {
        on: {
          submit: async (event) => {
            event.preventDefault();
            if (state.inviteBusy) return;
            state.inviteBusy = true;
            state.inviteError = null;
            draw();
            try {
              state.newCode = await coachData.createInvite(labelInput.value);
            } catch (error) {
              state.inviteError = api.userFacingMessage(error);
            } finally {
              state.inviteBusy = false;
              draw();
            }
          },
        },
      }, [
        el("div", { className: "stack" }, [
          field("Label (only you see this)", labelInput),
          el("div", { className: "row" }, [
            button(state.inviteBusy ? "Creating…" : "Create code", { type: "submit", disabled: state.inviteBusy }),
            button("Cancel", {
              variant: "btn--secondary",
              onClick: () => { state.invitePanelOpen = false; state.inviteError = null; draw(); },
            }),
          ]),
          state.inviteError
            ? banner("error", "Couldn't create the code", state.inviteError.message, state.inviteError.code)
            : null,
        ]),
      ]),
    ]);
  }

  function emptyRoster() {
    return card([
      eyebrow("Clients"),
      el("h2", { className: "card__title", text: "Nobody linked yet" }),
      el("p", { className: "muted", text: "Create an invite code above and send it to a client. As soon as they enter it, their sessions appear here — and on your phone." }),
    ]);
  }

  function clientList() {
    return el("div", { className: "card card--flush" }, [
      el("ul", { className: "client-list" },
        state.clients.map((client) => el("li", { className: "client-list__item" }, [clientRow(client)])),
      ),
    ]);
  }

  function clientRow(client) {
    const reason = reasonFor(client);
    const days = daysSinceLastSession(client);
    const detail = client.lastSessionAt
      ? `Last session ${relativeDays(days) === "Today" ? "today" : `${relativeDays(days)} ago`} · ${pluralize(client.sessionsLast14Days, "session")} in 14 days${client.latestMovement ? ` · ${client.latestMovement}` : ""}`
      : "No sessions analyzed yet";

    return el("button", {
      className: "client",
      attrs: { type: "button" },
      on: { click: () => onOpenClient?.(client) },
    }, [
      el("div", { className: "client__body" }, [
        el("div", { className: "client__name", text: client.displayName }),
        el("div", { className: "client__detail", text: detail }),
      ]),
      pill(reasonLabel(reason), needsAttention(reason) ? "pill--attention" : "pill--ok"),
      el("div", {
        className: `score score--${scoreTone(client.latestScore)}`,
        text: client.latestScore ?? "—",
      }),
      el("div", { className: "client__chevron", text: "›" }),
    ]);
  }

  function openInvitesCard() {
    const open = state.invites.filter(
      (invite) => !invite.redeemed && (!invite.expiresAt || invite.expiresAt > new Date()),
    );
    if (open.length === 0) return null;

    return card([
      eyebrow("Outstanding invites"),
      el("p", { className: "muted", text: "These count against your client limit until they are used or revoked." }),
      el("div", { className: "table-wrap" }, [
        el("table", { className: "table" }, [
          el("thead", {}, [
            el("tr", {}, [
              el("th", { text: "Code" }),
              el("th", { text: "Label" }),
              el("th", { text: "Expires" }),
              el("th", { text: "" }),
            ]),
          ]),
          el("tbody", {}, open.map((invite) => el("tr", {}, [
            el("td", { text: invite.code }),
            el("td", { text: invite.label || "—" }),
            el("td", { text: formatDate(invite.expiresAt) }),
            el("td", {}, [
              button("Revoke", {
                variant: "btn--danger btn--small",
                onClick: async () => {
                  try {
                    await coachData.revokeInvite(invite.code);
                  } catch (error) {
                    state.error = api.userFacingMessage(error);
                  }
                  load();
                },
              }),
            ]),
          ]))),
        ]),
      ]),
    ]);
  }

  function privacyNote() {
    return banner(
      "info",
      "Measurements only",
      "You see what Kinetriq measured: reps, joint angles, tempo, consistency scores, and assessment grades. Client video stays on the device that recorded it and is never uploaded, so there is nothing here to watch. If you need to see a rep, ask your client to share that clip directly.",
    );
  }

  load();
  return { reload: load };
}
