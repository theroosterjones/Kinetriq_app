import { el, render, card, button, banner, field, input } from "../dom.js";
import { config } from "../config.js";
import * as api from "../api.js";

/**
 * Sign-in.
 *
 * Two paths on purpose. A coach who created their account with Sign in with Apple on
 * the phone has no password, so the email link is not a "forgot password" fallback
 * here — for a good share of coaches it is the only way in.
 *
 * There is no sign-up. Accounts and subscriptions are created in the iOS app, and a
 * web signup form would produce accounts with no entitlement and no way to buy one.
 */
export function renderLogin(container, { onSignedIn, notice } = {}) {
  const state = { mode: "password", message: notice || null, busy: false };

  function draw() {
    const emailInput = input({
      type: "email", name: "email", placeholder: "you@example.com",
      autocomplete: "username", required: true,
    });
    const passwordInput = input({
      type: "password", name: "password", placeholder: "Your password",
      autocomplete: "current-password", required: true,
    });

    const submit = button(
      state.busy
        ? "Working…"
        : state.mode === "password" ? "Sign in" : "Email me a sign-in link",
      { type: "submit", disabled: state.busy },
    );

    const form = el("form", {
      on: {
        submit: async (event) => {
          event.preventDefault();
          if (state.busy) return;
          state.busy = true;
          state.message = null;
          draw();

          try {
            if (state.mode === "password") {
              await api.signInWithPassword(emailInput.value, passwordInput.value);
              onSignedIn?.();
              return;
            }
            await api.sendMagicLink(emailInput.value);
            state.mode = "sent";
            state.sentTo = emailInput.value.trim();
          } catch (error) {
            const { message, code } = api.authMessage(error);
            state.message = { kind: "error", title: "Couldn't sign in", message, code };
          } finally {
            state.busy = false;
            draw();
          }
        },
      },
    }, [
      el("div", { className: "stack" }, [
        field("Email", emailInput),
        state.mode === "password" ? field("Password", passwordInput) : null,
        submit,
      ]),
    ]);

    // Preserve what the user typed across redraws.
    if (state.email) emailInput.value = state.email;
    emailInput.addEventListener("input", () => { state.email = emailInput.value; });

    const body = state.mode === "sent"
      ? el("div", { className: "stack" }, [
          banner(
            "info",
            "Check your email",
            `We sent a sign-in link to ${state.sentTo}. Open it on this device — the link signs you in here. If you used Sign in with Apple, it goes to your Apple relay address.`,
          ),
          button("Use a different email", {
            variant: "btn--secondary",
            onClick: () => { state.mode = "password"; state.message = null; draw(); },
          }),
        ])
      : el("div", { className: "stack" }, [
          form,
          el("p", { className: "auth__switch" }, [
            state.mode === "password"
              ? el("button", {
                  className: "btn btn--link",
                  text: "Signed up with Apple, or no password? Email me a link instead",
                  attrs: { type: "button" },
                  on: { click: () => { state.mode = "link"; state.message = null; draw(); } },
                })
              : el("button", {
                  className: "btn btn--link",
                  text: "Use a password instead",
                  attrs: { type: "button" },
                  on: { click: () => { state.mode = "password"; state.message = null; draw(); } },
                }),
          ]),
        ]);

    render(container, [
      el("div", { className: "auth" }, [
        el("h1", { className: "auth__brand", text: "Kinetriq for Coaches" }),
        el("p", {
          className: "auth__tagline",
          text: "Sign in with the account you use in the Kinetriq app.",
        }),
        state.message
          ? banner(state.message.kind, state.message.title, state.message.message, state.message.code)
          : null,
        card([body]),
        el("div", { className: "stack" }, [
          el("p", { className: "tertiary", text: "New to Kinetriq? Create your account and subscribe in the iOS app — that is where coach plans are sold." }),
          config.appStoreURL
            ? el("p", {}, [
                el("a", {
                  attrs: { href: config.appStoreURL, rel: "noopener noreferrer", target: "_blank" },
                  text: "Get Kinetriq for iPhone",
                }),
              ])
            : null,
          el("p", { className: "tertiary", text: "This dashboard shows your clients' measurements. Client video never leaves their device and is not stored anywhere Kinetriq can reach." }),
        ]),
      ]),
    ]);
  }

  draw();
}
