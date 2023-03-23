
// ==UserScript==
// @name JSON Viewer
// @match *
// @run-at document-start
// ==/UserScript==

let pretags = document.querySelectorAll(
  '[style="word-wrap: break-word; white-space: pre-wrap;"]',
);

pretags.forEach(pre => {
  let text = pre.textContent;
  let parsed = JSON.parse(text);
  pre.textContent = JSON.stringify(parsed, null, 2);
});
