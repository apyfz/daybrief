import { useEffect, useState } from "react";
import { getSettings, type AppSettings } from "./bridge";
import { BriefView } from "./views/BriefView";
import { ConnectionsView } from "./views/ConnectionsView";
import { SettingsView } from "./views/SettingsView";
import { Onboarding } from "./views/Onboarding";

type Tab = "brief" | "connections" | "settings";

export function App() {
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [tab, setTab] = useState<Tab>("brief");

  useEffect(() => {
    getSettings().then(setSettings);
  }, []);

  if (!settings) return null;

  if (!settings.onboarded) {
    return <Onboarding onDone={() => getSettings().then(setSettings)} />;
  }

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">◓ Daybrief</div>
        <nav className="nav">
          <button
            className={tab === "brief" ? "active" : ""}
            onClick={() => setTab("brief")}
          >
            Today's brief
          </button>
          <button
            className={tab === "connections" ? "active" : ""}
            onClick={() => setTab("connections")}
          >
            Connections
          </button>
          <button
            className={tab === "settings" ? "active" : ""}
            onClick={() => setTab("settings")}
          >
            Settings
          </button>
        </nav>
      </aside>
      <main className="main">
        {tab === "brief" && <BriefView />}
        {tab === "connections" && <ConnectionsView />}
        {tab === "settings" && (
          <SettingsView settings={settings} onChange={setSettings} />
        )}
      </main>
    </div>
  );
}
