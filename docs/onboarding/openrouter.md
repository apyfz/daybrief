# Onboarding: OpenRouter (recommended AI provider)

Daybrief needs an AI model to turn your calendar, mail, and messages into a
single editorial brief. The simplest way to get started is **OpenRouter**: one
API key gives you access to many models (Anthropic, OpenAI, Google, and others)
behind a single endpoint, so you can switch models later without setting up a
new account.

This is the first step in onboarding. You can also use a direct provider key
(OpenAI, Anthropic, Gemini) or a local model via Ollama — but OpenRouter is the
recommended on-ramp.

Everything you paste here is stored in your macOS **Keychain** on your machine.
The only thing that leaves your Mac is the brief content you send to the model
you choose.

---

## 1. Create an OpenRouter account

1. Go to **<https://openrouter.ai>** and sign up (or sign in).
2. You can use most models pay-as-you-go. Add a small amount of credit, or set
   up billing, from your account's **Credits / Billing** page so your requests
   are not rejected for insufficient balance.

## 2. Create an API key

1. Open **<https://openrouter.ai/keys>** (Account → **Keys**).
2. Click **Create Key**, give it a name like `Daybrief`, and create it.
3. **Copy the key now.** It starts with `sk-or-`. OpenRouter shows the full key
   only once; if you lose it, create a new one.

Treat this key like a password. Anyone with it can spend your OpenRouter
credit.

## 3. Paste the key into Daybrief

1. In the Daybrief onboarding, on the **AI key** step, select **OpenRouter** as
   the provider.
2. Paste your `sk-or-...` key.
3. Daybrief makes a tiny test request to confirm the key works before letting
   you continue. If that round-trip fails, double-check the key and your
   OpenRouter credit balance.

The key is saved to your Keychain — Daybrief does not store it in plain text or
send it anywhere except OpenRouter.

## 4. Pick a model

1. After the key is verified, Daybrief loads the list of available models from
   OpenRouter (it queries OpenRouter's model list at runtime — model names are
   never hard-coded).
2. Choose a model for generating your brief.
   - A capable general-purpose model gives the best editorial quality.
   - Lighter or cheaper models cost less per brief and are fine for a quick
     summary.
   - You can change the model at any time later in **Settings**.

You can find each model's pricing and capabilities at
**<https://openrouter.ai/models>**.

---

## Notes

- **Cost:** Daybrief makes roughly one model call per brief (typically once per
  morning, plus any manual "generate now"). Cost depends on the model you pick;
  start cheap and move up if you want richer briefs.
- **Switching providers later:** If you would rather use OpenAI, Anthropic, or
  Gemini directly, or run a local model with Ollama, you can change the provider
  in Settings. OpenRouter is just the easiest place to begin.
- **Privacy:** Your brief content is sent to the provider you select so it can be
  summarized. Review OpenRouter's (and the underlying model provider's) data
  policies if that matters to you. For a fully local option, use Ollama.
