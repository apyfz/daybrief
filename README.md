<p align="center">
  <img src="docs/readme/masthead.svg" alt="Daybrief — Your morning, in focus. A daily edition for your Mac." width="100%">
</p>

<p align="center">
  <strong>Your calendar, inbox, conversations, and tasks. One thoughtful morning brief.</strong><br>
  Native to your Mac. Written by your chosen AI model. Ready in your menu bar.
</p>

<p align="center">
  <a href="https://github.com/apyfz/daybrief/releases/tag/v0.1.0">Download</a> ·
  <a href="#the-morning-edition">Take a look</a> ·
  <a href="#get-started">Get started</a> ·
  <a href="#your-tools-your-choice">Connections</a> ·
  <a href="#private-by-design">Privacy</a> ·
  <a href="CONTRIBUTING.md">Contribute</a>
</p>

<p align="center"><sub>macOS 26+ · Apple Silicon · v0.1.0 · Open source</sub></p>

---

## The morning edition

Daybrief gathers the things worth knowing and turns them into a small daily periodical: a painting, a golden masthead, a short overview, and the details that deserve your attention. Open a source when you want more context; follow an item back to the tool it came from.

<p align="center">
  <img src="docs/readme/brief.png" alt="Sample Daybrief edition with a painting, golden Wednesday masthead, morning overview, and expandable Gmail, Calendar, Slack, and Notion sections." width="420">
  <br><sub>Rendered from the app’s UI with fictional sample content. Artwork: Camille Pissarro, public domain.</sub>
</p>

| A calmer start | Made for your Mac | Yours to shape |
| :--- | :--- | :--- |
| A concise overview followed by source-by-source details. Quiet days stay quiet. | A menu-bar app, a daily delivery time, and catch-up when your Mac wakes. | Choose your AI provider, pick Slack channels, and edit the writing prompt and template. |

## Your tools, your choice

Connect only the sources you want in your edition.

| Tool | What it brings |
| :--- | :--- |
| <img src="Sources/DaybriefUI/Icons/gcal-color.png" width="22" alt=""> **Google Calendar** | Today and tomorrow’s events. |
| <img src="Sources/DaybriefUI/Icons/gmail-color.png" width="22" alt=""> **Gmail** | Unread and important mail, with support for multiple accounts. |
| <img src="Sources/DaybriefUI/Icons/slack-color.png" width="22" alt=""> **Slack** | Direct messages, mentions, and unread messages from channels you select. |
| **Notion** | Tasks due today or overdue in the databases you share. |

Choose **OpenRouter, OpenAI, Anthropic, or Gemini**, or use **Ollama** to write your brief locally. You can change your provider and model in Settings.

<details>
<summary><strong>A look inside Settings</strong></summary>
<br>
<img src="docs/readme/settings.png" alt="Daybrief settings with the Your Morning in focus artwork sidebar and the daily delivery time control." width="820">
<br>
<sub>Rendered with sample settings; native controls appear in the running app.</sub>
</details>

## Get started

Download **[Daybrief v0.1.0](https://github.com/apyfz/daybrief/releases/tag/v0.1.0)** for Apple Silicon and macOS 26+. Unzip the download and move Daybrief.app to Applications. This build is not notarized; see the release notes for installation details. The desktop widget is not included in this download.

Open Daybrief and look for the **sun icon in your menu bar**. It stays out of your Dock.

### Make it yours

1. **Choose a model.** Add your provider’s API key, or configure Ollama locally.
2. **Connect your tools.** The app walks you through the credentials and permissions for each service. You can skip sources and add them later.
3. **Set your delivery time.** Your edition is prepared daily; if your Mac is asleep, it catches up when you wake it.

### Connection guides

Daybrief connects directly to services using credentials you provide. Setup takes a little more work, but there is no Daybrief account or intermediary server.

- **[Google Calendar & Gmail](docs/onboarding/google.md)** — create a Google Desktop OAuth client.
- **[Slack](docs/onboarding/slack.md)** — create an internal Slack app and supply its user token.
- **Notion** — follow the in-app guide to create an integration and share your task databases.
- **[OpenRouter](docs/onboarding/openrouter.md)** — add a key and choose a model.

## Private by design

**No Daybrief account. No Daybrief server.** You connect your own tools and choose the model that writes your brief.

Your keys stay in your Mac’s Keychain. If you choose a cloud AI provider, the content needed for your brief is sent to that provider. Choose Ollama to write the brief locally on your Mac.

Read the [privacy and security details](SECURITY.md) for more about storage and data handling.

## Made for your mornings

Daybrief is a native Mac app, available for **macOS 26 or later on Apple Silicon**.

Want to build it yourself or contribute? See the [developer guide](docs/readme/development.md) and [contributing notes](CONTRIBUTING.md).

---

<p align="center">
  <strong>Make mornings a little clearer.</strong><br>
  <a href="CONTRIBUTING.md">Contributing</a> · <a href="CLA.md">Contributor agreement</a> · <a href="LICENSE">AGPL-3.0-only</a> · <a href="SECURITY.md">Security</a>
</p>
