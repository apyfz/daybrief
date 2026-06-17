// Render step (SPEC.md §3 step 6): structured brief → HTML, used both for the
// in-app view and the email / web-archive copy (§13 v1). Self-contained inline
// styles so the HTML stands alone as an archive file or email body.

import type { BriefEntry, BriefSection, StructuredBrief } from "@/core/brief";

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderEntry(entry: BriefEntry): string {
  const dot =
    entry.priority === 3 ? "🔴" : entry.priority === 2 ? "🟡" : "⚪️";
  const headline = entry.url
    ? `<a href="${esc(entry.url)}" style="color:#0a7;text-decoration:none">${esc(entry.headline)}</a>`
    : esc(entry.headline);
  const detail = entry.detail
    ? `<div class="detail">${esc(entry.detail)}</div>`
    : "";
  const people = entry.people?.length
    ? `<div class="people">${esc(entry.people.join(", "))}</div>`
    : "";
  return `<li class="entry"><span class="dot">${dot}</span><div><div class="headline">${headline}</div>${detail}${people}</div></li>`;
}

function renderSection(section: BriefSection): string {
  if (!section.entries.length) return "";
  const entries = section.entries.map(renderEntry).join("\n");
  return `<section class="section">
  <h2>${esc(section.title)}</h2>
  <ul>${entries}</ul>
</section>`;
}

/** Inner HTML fragment (no <html>/<body>), for embedding in the in-app view. */
export function renderBriefFragment(brief: StructuredBrief): string {
  const summary = brief.summary
    ? `<p class="summary">${esc(brief.summary)}</p>`
    : "";
  const sections = brief.sections
    .map(renderSection)
    .filter(Boolean)
    .join("\n");
  const body =
    sections || `<p class="empty">Nothing to brief today.</p>`;
  return `<div class="daybrief"><header><h1>Daybrief</h1><div class="date">${esc(brief.date)}</div></header>${summary}${body}</div>`;
}

const STYLE = `
  body{font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#1a1a1a;background:#fafafa;margin:0;padding:24px}
  .daybrief{max-width:680px;margin:0 auto;background:#fff;border-radius:12px;padding:28px 32px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
  header{display:flex;align-items:baseline;justify-content:space-between;border-bottom:1px solid #eee;padding-bottom:12px;margin-bottom:16px}
  h1{font-size:20px;margin:0;letter-spacing:-.02em}
  .date{color:#888;font-size:13px}
  .summary{color:#444;font-size:15px;margin:0 0 20px}
  .section{margin:20px 0}
  h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:#888;margin:0 0 10px}
  ul{list-style:none;margin:0;padding:0}
  .entry{display:flex;gap:10px;padding:8px 0;border-bottom:1px solid #f3f3f3}
  .dot{font-size:11px;line-height:1.6;flex-shrink:0}
  .headline{font-weight:500}
  .detail{color:#666;font-size:13px;margin-top:2px}
  .people{color:#999;font-size:12px;margin-top:2px}
  .empty,.daybrief .empty{color:#999}
`;

/** Full standalone HTML document, for the email / web-archive copy. */
export function renderBriefDocument(brief: StructuredBrief): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Daybrief — ${esc(brief.date)}</title>
<style>${STYLE}</style>
</head>
<body>
${renderBriefFragment(brief)}
</body>
</html>`;
}

/** Plain-text fallback (e.g. for notifications or low-fi email part). */
export function renderBriefText(brief: StructuredBrief): string {
  const lines: string[] = [`Daybrief — ${brief.date}`];
  if (brief.summary) lines.push("", brief.summary);
  for (const section of brief.sections) {
    if (!section.entries.length) continue;
    lines.push("", section.title.toUpperCase());
    for (const e of section.entries) {
      lines.push(`  • ${e.headline}`);
      if (e.detail) lines.push(`    ${e.detail}`);
    }
  }
  return lines.join("\n");
}
