# Icons

Connector glyphs, as **filled** brand marks so each source reads as itself.

| File          | Used for        | Source                                          | License |
| ------------- | --------------- | ----------------------------------------------- | ------- |
| `slack.pdf`   | Slack           | [Bootstrap Icons](https://icons.getbootstrap.com) | MIT     |
| `gmail.pdf`   | Gmail           | [Simple Icons](https://simpleicons.org)          | CC0 1.0 |
| `gcal.pdf`    | Google Calendar | Simple Icons                                     | CC0 1.0 |
| `notion.pdf`  | Notion          | Simple Icons                                     | CC0 1.0 |
| `hash.pdf`    | Public Slack channel  | [Hugeicons](https://hugeicons.com) free set | MIT |
| `lock.pdf`    | Private Slack channel | Hugeicons free set                     | MIT     |

Slack comes from Bootstrap Icons because Simple Icons removed its Slack mark following
a trademark request. The two channel markers stay stroke-style: neither the free
Hugeicons tier nor Lucide ships filled variants, and a "filled hash" isn't a thing.

The brand logos are trademarks of their owners; they're used here only to identify the
service each section comes from.

## Why PDFs, not an asset catalog

SwiftPM copies an `.xcassets` into the resource bundle **without running `actool`**, so
asset-catalog lookups fail in the `swift build` products the snapshot tools use — it
would only work in the Xcode build. `DaybriefIcon` loads each PDF as a template
`NSImage`, which works in both.

The PDFs were generated from the upstream SVGs with a small WebKit-based converter
(`WKWebView.createPDF`), since the icons use arc and smooth-curve path commands that a
hand-rolled parser would get wrong.

Add a new icon by dropping its PDF here and naming it in `DaybriefIcon`.

## Full-colour connection marks

Settings uses these original-colour PNGs, downloaded from the services' own asset hosts:

- `gcal-color.png`: https://www.gstatic.com/images/branding/product/2x/calendar_2020q4_48dp.png
- `gmail-color.png`: https://www.gstatic.com/images/branding/product/2x/gmail_2020q4_48dp.png
- `slack-color.png`: https://a.slack-edge.com/80588/marketing/img/icons/icon_slack_hash_colored.png

These remain their owners' trademarks, used solely to identify the connected service.
Notion keeps its monochrome mark. The brief's existing template glyphs are unchanged.
