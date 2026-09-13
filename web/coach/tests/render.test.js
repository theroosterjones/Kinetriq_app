import { test } from "node:test";
import assert from "node:assert/strict";

/**
 * Renders the roster and client views for real, against fake Supabase responses.
 *
 * The seam is `globalThis.fetch`, so this exercises the whole stack the browser runs:
 * `api.js` transport and token handling, `coach.js` queries, the triage ordering, and
 * the DOM construction in the views. What it cannot check is layout — that needs a
 * browser — but it does catch the failure that matters most here, which is a view that
 * throws or silently drops data because a column name or a shape was wrong.
 *
 * The fake DOM below implements only what `js/dom.js` actually uses. If it needs
 * something new, that is a signal `dom.js` grew a dependency worth noticing.
 */

class FakeText {
  constructor(text) { this.nodeType = 3; this._text = String(text); }
  get textContent() { return this._text; }
}

class FakeElement {
  constructor(tag) {
    this.nodeType = 1;
    this.tagName = tag.toUpperCase();
    this.children = [];
    this.attributes = {};
    this.dataset = {};
    this.listeners = {};
    this.className = "";
    this._text = null;
  }

  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() {
    if (this._text !== null) return this._text;
    return this.children.map((child) => child.textContent).join("");
  }

  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return this.attributes[name] ?? null; }
  addEventListener(event, handler) { (this.listeners[event] ||= []).push(handler); }
  appendChild(child) { this.children.push(child); return child; }
  removeChild(child) { this.children = this.children.filter((c) => c !== child); return child; }
  get firstChild() { return this.children[0] || null; }

  /** Depth-first text of the rendered tree, for assertions. */
  get allText() { return this.textContent; }

  find(predicate) {
    if (predicate(this)) return this;
    for (const child of this.children) {
      if (child instanceof FakeElement) {
        const hit = child.find(predicate);
        if (hit) return hit;
      }
    }
    return null;
  }

  findAll(predicate, out = []) {
    if (predicate(this)) out.push(this);
    for (const child of this.children) {
      if (child instanceof FakeElement) child.findAll(predicate, out);
    }
    return out;
  }
}

function installFakeDOM() {
  globalThis.document = {
    createElement: (tag) => new FakeElement(tag),
    createTextNode: (text) => new FakeText(text),
  };
  return new FakeElement("div");
}

function installStorage(entries = {}) {
  const map = new Map(Object.entries(entries));
  globalThis.localStorage = {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, v),
    removeItem: (k) => map.delete(k),
  };
}

const COACH_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";

function signedInSession() {
  return JSON.stringify({
    accessToken: "test-access-token",
    refreshToken: "test-refresh-token",
    // Far future so nothing tries to refresh mid-test.
    expiresAt: Math.floor(Date.now() / 1000) + 86_400,
    user: { id: COACH_ID, email: "coach@example.com" },
  });
}

const NOW = Date.now();
const daysAgo = (days) => new Date(NOW - days * 86_400_000).toISOString();

const ROSTER = [
  {
    client_user_id: "11111111-1111-1111-1111-111111111111",
    display_name: "Zoe Steady",
    status: "active",
    linked_at: daysAgo(90),
    last_session_at: daysAgo(1),
    sessions_last_14_days: 5,
    latest_score: 84,
    previous_score: 83,
    latest_movement: "Squat",
    open_asymmetry_flag: false,
  },
  {
    client_user_id: "22222222-2222-2222-2222-222222222222",
    display_name: "Ada Newlink",
    status: "active",
    linked_at: daysAgo(3),
    last_session_at: null,
    sessions_last_14_days: 0,
    latest_score: null,
    previous_score: null,
    latest_movement: null,
    open_asymmetry_flag: false,
  },
  {
    client_user_id: "33333333-3333-3333-3333-333333333333",
    display_name: "Bo Quiet",
    status: "active",
    linked_at: daysAgo(200),
    last_session_at: daysAgo(21),
    sessions_last_14_days: 0,
    latest_score: 70,
    previous_score: 72,
    latest_movement: "Deadlift",
    open_asymmetry_flag: false,
  },
];

const SESSIONS = [
  {
    id: "aaaa1111-1111-1111-1111-111111111111",
    user_id: "11111111-1111-1111-1111-111111111111",
    recorded_at: "2026-09-01T14:32:11.482913+00:00",
    kind: "exercise",
    movement_key: "Squat",
    movement_name: "Squat",
    side: "right",
    source: "liveCamera",
    duration_seconds: 41.5,
    pose_detection_rate: 0.94,
    total_reps: 2,
    score: 84,
    mean_peak_angle_deg: 88.4,
    asymmetry_flag: false,
    insights: ["Depth held across the set"],
    analysis_reps: [
      { rep_number: 2, peak_flexion_angle_deg: 90, eccentric_seconds: 3.2, pause_bottom_seconds: 0.4, concentric_seconds: 1.7, pause_top_seconds: 0.6 },
      { rep_number: 1, peak_flexion_angle_deg: 86.8, eccentric_seconds: 2.0, pause_bottom_seconds: 0.2, concentric_seconds: 1.3, pause_top_seconds: 0.5 },
    ],
  },
  {
    id: "bbbb2222-2222-2222-2222-222222222222",
    user_id: "11111111-1111-1111-1111-111111111111",
    recorded_at: "2026-08-14T09:00:00Z",
    kind: "assessment",
    movement_key: "Shoulder Flexion",
    movement_name: "Shoulder Flexion",
    side: "left",
    plane: "frontal",
    source: "savedVideo",
    duration_seconds: 12,
    // Deliberately poor tracking so the caveat banner has to appear.
    pose_detection_rate: 0.42,
    total_reps: 0,
    score: null,
    grade: "B",
    left_rom_deg: 158,
    right_rom_deg: 171,
    asymmetry_deg: 13,
    asymmetry_flag: true,
    sub_grades: [{ label: "Range", grade: "B" }],
    details: ["Left side lagged through the top third"],
    analysis_reps: [],
  },
];

/** Records every request so tests can assert what was actually asked for. */
function installFetch({ coachRow = { user_id: COACH_ID, display_name: "Coach", client_limit: 15 } } = {}) {
  const calls = [];

  globalThis.fetch = async (url, options = {}) => {
    const target = new URL(String(url));
    calls.push({ url: target, method: options.method || "GET", headers: options.headers, body: options.body });

    const json = (payload, status = 200) => ({
      ok: status >= 200 && status < 300,
      status,
      text: async () => JSON.stringify(payload),
    });

    if (target.pathname.endsWith("/rest/v1/coaches")) return json(coachRow ? [coachRow] : []);
    if (target.pathname.endsWith("/rest/v1/rpc/coach_roster")) return json(ROSTER);
    if (target.pathname.endsWith("/rest/v1/coach_invites")) return json([]);
    if (target.pathname.endsWith("/rest/v1/analysis_records")) return json(SESSIONS);

    throw new Error(`Unexpected request: ${target.pathname}`);
  };

  return calls;
}

/** Lets the views' `load()` promises settle. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function loadModules() {
  globalThis.KINETRIQ_CONFIG = {
    supabaseUrl: "https://test-project.supabase.co",
    supabaseAnonKey: "test-anon-key-that-is-long-enough-to-pass-validation",
  };
  // Dynamic import so the globals above are in place before config.js reads them.
  return {
    roster: await import("../js/views/roster.js"),
    client: await import("../js/views/client.js"),
    triage: await import("../js/triage.js"),
  };
}

test("the roster renders in triage order with the signals a coach acts on", async () => {
  const container = installFakeDOM();
  installStorage({ "kinetriq.coach.session": signedInSession() });
  const calls = installFetch();
  const { roster } = await loadModules();

  roster.renderRoster(container, {});
  await settle();

  const text = container.allText;
  assert.match(text, /Ada Newlink/);
  assert.match(text, /Bo Quiet/);
  assert.match(text, /Zoe Steady/);

  // Two of the three need a look: never started, and quiet for 21 days. Zoe's +1 point
  // is inside the noise band, so she is on track and is not counted.
  assert.match(text, /2 need a look/);

  const names = container
    .findAll((node) => node.className === "client__name")
    .map((node) => node.textContent);
  assert.deepEqual(names, ["Ada Newlink", "Bo Quiet", "Zoe Steady"]);

  const pills = container.findAll((node) => node.className.startsWith("pill ")).map((n) => n.textContent);
  assert.ok(pills.includes("Hasn't started"), `expected a "Hasn't started" pill, got ${pills.join(", ")}`);
  assert.ok(pills.includes("Quiet 21 days"), `expected a quiet pill, got ${pills.join(", ")}`);
  assert.ok(pills.includes("On track"));

  // A client with no sessions must show an em dash, not a zero. "0" would read as a
  // score of zero, which is a very different message to give a coach.
  const scores = container.findAll((node) => node.className.startsWith("score ")).map((n) => n.textContent);
  assert.deepEqual(scores, ["—", "70", "84"]);

  assert.match(text, /Client video stays on the device that recorded it/);
});

test("the roster scopes every read to the signed-in coach and sends the token", async () => {
  const container = installFakeDOM();
  installStorage({ "kinetriq.coach.session": signedInSession() });
  const calls = installFetch();
  const { roster } = await loadModules();

  roster.renderRoster(container, {});
  await settle();

  const coaches = calls.find((call) => call.url.pathname.endsWith("/coaches"));
  assert.equal(coaches.url.searchParams.get("user_id"), `eq.${COACH_ID}`);
  assert.equal(coaches.headers.Authorization, "Bearer test-access-token");
  assert.equal(coaches.headers.apikey, "test-anon-key-that-is-long-enough-to-pass-validation");

  const invites = calls.find((call) => call.url.pathname.endsWith("/coach_invites"));
  assert.equal(invites.url.searchParams.get("coach_user_id"), `eq.${COACH_ID}`);
});

test("an account with no coaches row is told to subscribe in the app, not shown an empty roster", async () => {
  const container = installFakeDOM();
  installStorage({ "kinetriq.coach.session": signedInSession() });
  installFetch({ coachRow: null });
  const { roster } = await loadModules();

  roster.renderRoster(container, {});
  await settle();

  assert.match(container.allText, /isn't a coach account/);
  assert.match(container.allText, /Coach plans are bought in the Kinetriq iOS app/);
  assert.doesNotMatch(container.allText, /Create invite code/);
});

test("a lapsed coach keeps read access but cannot create invites", async () => {
  const container = installFakeDOM();
  installStorage({ "kinetriq.coach.session": signedInSession() });
  installFetch({ coachRow: { user_id: COACH_ID, display_name: "Coach", client_limit: 0 } });
  const { roster } = await loadModules();

  roster.renderRoster(container, {});
  await settle();

  assert.match(container.allText, /Coach plan isn't active/);
  assert.match(container.allText, /Nobody has been unlinked/);
  assert.match(container.allText, /Zoe Steady/, "existing clients stay visible");

  const inviteButton = container.find((node) => node.tagName === "BUTTON" && node.textContent === "Create invite code");
  assert.equal(inviteButton.getAttribute("disabled"), "true");
});

test("a client's sessions render with reps, tempo, and the tracking caveat", async () => {
  const container = installFakeDOM();
  installStorage({ "kinetriq.coach.session": signedInSession() });
  const calls = installFetch();
  const { client, triage } = await loadModules();

  const zoe = triage.sortClients(
    [{
      clientUserID: "11111111-1111-1111-1111-111111111111",
      displayName: "Zoe Steady",
      status: "active",
      linkedAt: new Date(NOW - 90 * 86_400_000),
      lastSessionAt: new Date(NOW - 86_400_000),
      sessionsLast14Days: 5,
      latestScore: 84,
      previousScore: 83,
      latestMovement: "Squat",
      openAsymmetryFlag: false,
    }],
  )[0];

  client.renderClient(container, zoe, {});
  await settle();

  const text = container.allText;
  assert.match(text, /Zoe Steady/);
  assert.match(text, /Squat/);
  assert.match(text, /Shoulder Flexion/);

  // Only the client's own rows, and the filter is explicit rather than trusting RLS.
  const read = calls.find((call) => call.url.pathname.endsWith("/analysis_records"));
  assert.equal(read.url.searchParams.get("user_id"), "eq.11111111-1111-1111-1111-111111111111");
  assert.equal(read.url.searchParams.get("select"), "*,analysis_reps(*)");

  // Expand the exercise session.
  const detailButtons = container.findAll((node) => node.tagName === "BUTTON" && node.textContent === "Detail");
  assert.equal(detailButtons.length, 2);
  detailButtons[0].listeners.click[0]({});
  await settle();

  const expanded = container.allText;
  assert.match(expanded, /2 reps/);
  assert.match(expanded, /Depth held across the set/);
  // Averages are 2.6 / 0.3 / 1.5 / 0.55 → 3-0-1-0 for the set, while rep 2 on its own
  // is 3-0-2-1. Both have to appear, in the right places.
  assert.match(expanded, /3-0-1-0/, "set average tempo");
  assert.match(expanded, /3-0-2-1/, "rep 2 tempo");
  assert.match(expanded, /88°/, "mean peak angle");
});

test("a poorly tracked session says so where the numbers are", async () => {
  const container = installFakeDOM();
  installStorage({ "kinetriq.coach.session": signedInSession() });
  installFetch();
  const { client } = await loadModules();

  client.renderClient(container, {
    clientUserID: "11111111-1111-1111-1111-111111111111",
    displayName: "Zoe Steady",
    status: "active",
    linkedAt: new Date(),
    lastSessionAt: new Date(),
    sessionsLast14Days: 5,
    latestScore: 84,
    previousScore: 83,
    latestMovement: "Squat",
    openAsymmetryFlag: false,
  }, {});
  await settle();

  // The assessment row is the 42%-tracked one.
  const detailButtons = container.findAll((node) => node.tagName === "BUTTON" && node.textContent === "Detail");
  detailButtons[1].listeners.click[0]({});
  await settle();

  const text = container.allText;
  assert.match(text, /Pose tracked 42% of frames/);
  assert.match(text, /indicative rather than exact/);
  assert.match(text, /Left side lagged through the top third/);
  assert.match(text, /Range: B/, "sub-grade");
  assert.match(text, /13°/, "asymmetry");
});

test("no client surface offers video, because there is none to offer", async () => {
  const container = installFakeDOM();
  installStorage({ "kinetriq.coach.session": signedInSession() });
  installFetch();
  const { client } = await loadModules();

  client.renderClient(container, {
    clientUserID: "11111111-1111-1111-1111-111111111111",
    displayName: "Zoe Steady",
    status: "active",
    linkedAt: new Date(),
    lastSessionAt: new Date(),
    sessionsLast14Days: 5,
    latestScore: 84,
    previousScore: 83,
    latestMovement: "Squat",
    openAsymmetryFlag: false,
  }, {});
  await settle();

  assert.equal(container.find((node) => node.tagName === "VIDEO"), null);
  assert.equal(container.find((node) => node.tagName === "IFRAME"), null);
  assert.match(container.allText, /No video, by design/);
  assert.match(container.allText, /stays on the device that recorded it/);
});
