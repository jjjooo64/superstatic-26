// Example loader.js
// Copy into your content repo and adapt BASE + scripts.
// Scripts are loaded sequentially (each waits for the previous to finish)
// and cache-busted on every page load.

const BASE = "https://your-user.github.io/your-content-repo";
const scripts = [
  "first.js",
  "second.js"
];

const v = Date.now();

function loadSequential(list, index = 0) {
  if (index >= list.length) return;
  const s = document.createElement("script");
  s.src = `${BASE}/${list[index]}?v=${v}`;
  s.onload = () => loadSequential(list, index + 1);
  s.onerror = () => console.error("Failed to load", list[index]);
  document.head.appendChild(s);
}

loadSequential(scripts);
