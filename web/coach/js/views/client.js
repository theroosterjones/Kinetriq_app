import { el, render, card, eyebrow, button, banner, pill } from "../dom.js";
import * as api from "../api.js";
import * as coachData from "../coach.js";
import * as csv from "../csv.js";
import { reasonFor, reasonLabel, needsAttention, daysSinceLastSession, scoreDelta } from "../triage.js";
import {
  averageTempo, formatDate, formatDateTime, formatDegrees, formatPercent,
  parseDate, pluralize, relativeDays, scoreTone, tempoString,
} from "../format.js";

/**
 * One client's history.
 *
 * This is the screen the browser is genuinely better at than the phone: a session
 * table with per-rep detail is a lot of numbers, and a coach reviewing a week of
 * clients wants them side by side. The phone shows the same roster signals and links
 * out to the same sessions; nothing here is a separate dataset.
 *
 * There is no video, and not because it is hidden. `analysis_records` has no video
 * column and there is no storage bucket — the tables cannot answer the question.
 */
export function renderClient(container, client, { onBack } = {}) {
  const state = { loading: true, error: null, sessions: [], expanded: new Set(), removing: false };

  async function load() {
    state.loading = true;
    draw();
    try {
      state.sessions = (await coachData.fetchClientSessions(client.clientUserID)) || [];
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
        el("div", { className: "stack" }, sections()),
      ]),
    ]);
  }

  function topbar() {
    return el("header", { className: "topbar" }, [
      button("‹ Roster", { variant: "btn--secondary btn--small", onClick: () => onBack?.() }),
      el("div", {}, [
        el("h1", { className: "topbar__title", text: client.displayName }),
        el("p", {
          className: "topbar__meta",
          text: client.linkedAt ? `Linked since ${formatDate(client.linkedAt)}` : "Linked client",
        }),
      ]),
      el("div", { className: "topbar__spacer" }),
      el("div", { className: "topbar__actions" }, [
        button("Export sessions CSV", {
          variant: "btn--secondary btn--small",
          disabled: state.sessions.length === 0,
          onClick: () => csv.download(csv.sessionRows(state.sessions), `kinetriq-${client.displayName}-sessions`),
        }),
        button("Export reps CSV", {
          variant: "btn--secondary btn--small",
          disabled: state.sessions.length === 0,
          onClick: () => csv.download(csv.repRows(state.sessions), `kinetriq-${client.displayName}-reps`),
        }),
        button(state.removing ? "Confirm remove" : "Remove client", {
          variant: "btn--danger btn--small",
          onClick: onRemoveClicked,
        }),
      ]),
    ]);
  }

  async function onRemoveClicked() {
    // Two taps instead of a modal: the second press is the confirmation, and the label
    // says so. Removing is reversible by re-inviting, so a dialog would be theatre.
    if (!state.removing) {
      state.removing = true;
      draw();
      return;
    }
    try {
      await coachData.removeClient(client.clientUserID);
      onBack?.({ reload: true });
    } catch (error) {
      state.error = api.userFacingMessage(error);
      state.removing = false;
      draw();
    }
  }

  function sections() {
    return [
      state.removing
        ? banner("warning", "Press “Confirm remove” again to unlink", `You'll stop seeing ${client.displayName}'s measurements. Their own history is untouched, and they can be re-invited later.`)
        : null,
      statusCard(),
      adherenceCard(),
      state.error ? banner("error", "Couldn't load sessions", state.error.message, state.error.code) : null,
      state.loading ? card([el("p", { className: "muted", text: "Loading sessions…" })]) : sessionsCard(),
      privacyNote(),
    ].filter(Boolean);
  }

  function statusCard() {
    const reason = reasonFor(client);
    const delta = scoreDelta(client);

    return card([
      eyebrow("Latest"),
      el("div", { className: "row" }, [
        el("div", { className: `score score--${scoreTone(client.latestScore)}`, text: client.latestScore ?? "—" }),
        el("div", {}, [
          pill(reasonLabel(reason), needsAttention(reason) ? "pill--attention" : "pill--ok"),
          delta !== null
            ? el("p", {
                className: delta >= 0 ? "delta--up" : "delta--down",
                text: delta >= 0
                  ? `Up ${pluralize(delta, "point")} from the session before`
                  : `Down ${pluralize(Math.abs(delta), "point")} from the session before`,
              })
            : null,
          client.latestMovement
            ? el("p", { className: "muted", text: `Last analyzed: ${client.latestMovement}` })
            : null,
        ]),
      ]),
      client.openAsymmetryFlag
        ? banner("warning", "Asymmetry flagged", "An assessment in the last 30 days showed a side-to-side difference large enough to flag. Worth reviewing before adding load.")
        : null,
    ].filter(Boolean));
  }

  function adherenceCard() {
    const days = daysSinceLastSession(client);
    return card([
      eyebrow("Adherence"),
      el("div", { className: "grid-2" }, [
        stat(String(client.sessionsLast14Days), "Sessions, last 14 days"),
        stat(relativeDays(days), "Since last session"),
        stat(String(state.sessions.length), "Sessions on record"),
      ]),
    ]);
  }

  function stat(value, label) {
    return el("div", { className: "stat" }, [
      el("div", { className: "stat__value", text: value }),
      el("div", { className: "stat__label", text: label }),
    ]);
  }

  function sessionsCard() {
    if (state.sessions.length === 0) {
      return card([
        eyebrow("Sessions"),
        el("h2", { className: "card__title", text: "Nothing analyzed yet" }),
        el("p", { className: "muted", text: "Sessions appear here as soon as this client analyzes a set or an assessment with sync turned on." }),
      ]);
    }

    const rows = [];
    for (const record of state.sessions) {
      rows.push(sessionRow(record));
      if (state.expanded.has(record.id)) rows.push(expandedRow(record));
    }

    return el("div", { className: "card card--flush" }, [
      el("div", { className: "table-wrap" }, [
        el("table", { className: "table" }, [
          el("thead", {}, [
            el("tr", {}, [
              el("th", { text: "Date" }),
              el("th", { text: "Movement" }),
              el("th", { text: "Reps" }),
              el("th", { text: "Score" }),
              el("th", { text: "Grade" }),
              el("th", { text: "Depth" }),
              el("th", { text: "Tempo" }),
              el("th", { text: "Tracking" }),
              el("th", { text: "" }),
            ]),
          ]),
          el("tbody", {}, rows),
        ]),
      ]),
    ]);
  }

  function sessionRow(record) {
    const isExercise = (record.kind || "exercise") === "exercise";
    const isOpen = state.expanded.has(record.id);

    return el("tr", { className: isOpen ? "is-open" : "" }, [
      el("td", { text: formatDateTime(parseDate(record.recorded_at)) }),
      el("td", { text: record.movement_name || record.movement_key || "—" }),
      el("td", { className: "num", text: isExercise ? String(record.total_reps ?? 0) : "—" }),
      el("td", { className: "num", text: record.score ?? "—" }),
      el("td", { text: record.grade || "—" }),
      el("td", { className: "num", text: formatDegrees(record.mean_peak_angle_deg) }),
      el("td", { className: "num", text: averageTempo(record.analysis_reps) || "—" }),
      el("td", { className: "num", text: formatPercent(record.pose_detection_rate) }),
      el("td", {}, [
        button(isOpen ? "Hide" : "Detail", {
          variant: "btn--secondary btn--small",
          onClick: () => {
            if (isOpen) state.expanded.delete(record.id);
            else state.expanded.add(record.id);
            draw();
          },
        }),
      ]),
    ]);
  }

  function expandedRow(record) {
    return el("tr", {}, [
      el("td", { className: "expand", attrs: { colspan: "9" } }, [
        el("div", { className: "stack" }, [
          trackingCaveat(record),
          repTable(record),
          assessmentDetail(record),
          notesList("Coaching notes recorded with this session", record.insights),
          notesList("Assessment detail", record.details),
        ].filter(Boolean)),
      ]),
    ]);
  }

  /**
   * The tracking rate is the honest caveat on everything else in the row. A set where
   * pose was detected in 30% of frames has real numbers attached to it, and they mean
   * much less than the same numbers at 95%.
   */
  function trackingCaveat(record) {
    const rate = Number(record.pose_detection_rate);
    if (!Number.isFinite(rate) || rate >= 0.7) return null;
    return banner(
      "warning",
      `Pose tracked ${formatPercent(rate)} of frames`,
      "Treat these measurements as indicative rather than exact. Lighting, framing, or a mismatched camera angle usually explains it.",
    );
  }

  function repTable(record) {
    const reps = [...(record.analysis_reps || [])].sort((a, b) => a.rep_number - b.rep_number);
    if (reps.length === 0) return null;

    return el("div", {}, [
      eyebrow(pluralize(reps.length, "rep")),
      el("div", { className: "table-wrap" }, [
        el("table", { className: "table" }, [
          el("thead", {}, [
            el("tr", {}, [
              el("th", { text: "Rep" }),
              el("th", { text: "Peak angle" }),
              el("th", { text: "Tempo" }),
              el("th", { text: "Ecc" }),
              el("th", { text: "Pause btm" }),
              el("th", { text: "Con" }),
              el("th", { text: "Pause top" }),
            ]),
          ]),
          el("tbody", {}, reps.map((rep) => el("tr", {}, [
            el("td", { className: "num", text: String(rep.rep_number) }),
            el("td", { className: "num", text: formatDegrees(rep.peak_flexion_angle_deg, 1) }),
            el("td", { className: "num", text: tempoString(
              rep.eccentric_seconds || 0, rep.pause_bottom_seconds || 0,
              rep.concentric_seconds || 0, rep.pause_top_seconds || 0,
            ) }),
            el("td", { className: "num", text: seconds(rep.eccentric_seconds) }),
            el("td", { className: "num", text: seconds(rep.pause_bottom_seconds) }),
            el("td", { className: "num", text: seconds(rep.concentric_seconds) }),
            el("td", { className: "num", text: seconds(rep.pause_top_seconds) }),
          ]))),
        ]),
      ]),
    ]);
  }

  function seconds(value) {
    const number = Number(value);
    return Number.isFinite(number) ? `${number.toFixed(2)}s` : "—";
  }

  function assessmentDetail(record) {
    if ((record.kind || "exercise") !== "assessment") return null;

    const subGrades = record.sub_grades || [];
    return el("div", {}, [
      eyebrow("Assessment"),
      el("div", { className: "grid-2" }, [
        stat(record.grade || "—", "Overall grade"),
        stat(formatDegrees(record.left_rom_deg), "Left range"),
        stat(formatDegrees(record.right_rom_deg), "Right range"),
        stat(formatDegrees(record.asymmetry_deg), "Asymmetry"),
      ]),
      subGrades.length > 0
        ? el("div", { className: "row" }, subGrades.map((sub) => pill(`${sub.label}: ${sub.grade}`)))
        : null,
    ].filter(Boolean));
  }

  function notesList(title, items) {
    if (!items || items.length === 0) return null;
    return el("div", {}, [
      eyebrow(title),
      el("ul", { className: "notes" }, items.map((item) => el("li", { text: item }))),
    ]);
  }

  function privacyNote() {
    return banner(
      "info",
      "No video, by design",
      `${client.displayName}'s footage stays on the device that recorded it. Kinetriq has no video storage, so there is nothing here to play and nothing for anyone else to request. Everything above is what the on-device analysis measured.`,
    );
  }

  load();
  return { reload: load };
}
