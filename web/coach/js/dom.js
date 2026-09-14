/**
 * Minimal DOM helpers.
 *
 * Every string that comes from Supabase — a client's display name, a coaching note,
 * a movement name — reaches the page through `textContent`, never `innerHTML`. That
 * is the whole reason this file exists instead of template strings: a coach's roster
 * is other people's data, and the session token lives in `localStorage`, so one
 * injected script tag would be enough to read a roster. There is no HTML-string path
 * in this app to get that wrong in.
 */

/**
 * @param {string} tag
 * @param {object} [props]  className, text, attrs, dataset, on, and children
 * @param {(Node|string|null|undefined|false)[]} [children]
 */
export function el(tag, props = {}, children = []) {
  const node = document.createElement(tag);

  if (props.className) node.className = props.className;
  if (props.text !== undefined && props.text !== null) node.textContent = String(props.text);

  for (const [key, value] of Object.entries(props.attrs || {})) {
    if (value !== null && value !== undefined && value !== false) {
      node.setAttribute(key, String(value));
    }
  }
  for (const [key, value] of Object.entries(props.dataset || {})) {
    node.dataset[key] = String(value);
  }
  for (const [event, handler] of Object.entries(props.on || {})) {
    node.addEventListener(event, handler);
  }

  append(node, children);
  return node;
}

export function append(parent, children) {
  const list = Array.isArray(children) ? children : [children];
  for (const child of list) {
    if (child === null || child === undefined || child === false) continue;
    parent.appendChild(typeof child === "string" ? document.createTextNode(child) : child);
  }
  return parent;
}

export function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
  return node;
}

/** Replaces a container's contents in one shot. */
export function render(container, children) {
  return append(clear(container), children);
}

export function card(children, className = "") {
  return el("div", { className: `card ${className}`.trim() }, children);
}

export function eyebrow(text) {
  return el("p", { className: "eyebrow", text });
}

export function button(label, { onClick, variant = "", disabled = false, type = "button" } = {}) {
  return el("button", {
    className: `btn ${variant}`.trim(),
    text: label,
    attrs: { type, disabled: disabled || false },
    on: onClick ? { click: onClick } : {},
  });
}

export function pill(text, tone = "") {
  return el("span", { className: `pill ${tone}`.trim(), text });
}

/**
 * Banner with an optional short reference code, matching the app's convention of
 * pairing plain-language guidance with something a user can screenshot.
 */
export function banner(kind, title, message, code) {
  return el("div", { className: `banner banner--${kind}` }, [
    el("div", { className: "banner__body" }, [
      el("p", { className: "banner__title", text: title }),
      el("p", { className: "banner__message" }, [
        message,
        code ? el("span", { className: "error-code", text: `Error code: ${code}` }) : null,
      ]),
    ]),
  ]);
}

export function field(labelText, input) {
  const id = input.id || `f-${Math.random().toString(36).slice(2, 9)}`;
  input.id = id;
  return el("div", { className: "field" }, [
    el("label", { className: "field__label", text: labelText, attrs: { for: id } }),
    input,
  ]);
}

export function input({ type = "text", name, placeholder, value = "", autocomplete, required = false }) {
  return el("input", {
    className: "input",
    attrs: { type, name, placeholder, value, autocomplete, required: required || false },
  });
}
