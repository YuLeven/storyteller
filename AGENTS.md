# Guidance for coding agents

## Protect the owner's model allowance

- Development and automated tests must use deterministic fake providers. Never make live model calls, perform OAuth consent, or fetch a live model catalog as part of a routine code change, test run, or benchmark.
- If the owner explicitly asks for a live gameplay exploration, use `gpt-6-luna` at low reasoning effort. Do not use Sol, Astra, or another more expensive model unless the owner explicitly requests that specific comparison.
- Do not start redundant or broad live runs. Record live usage only when the owner has asked for the exploration, and never treat a fake-provider test as evidence of live model behavior.

## Campaign and data boundaries

- Run Elixir commands in WSL and use the isolated test database for development checks.
- Use independently authored fictional campaigns such as Quiet Observatory for any authorized live gameplay exploration. Never access, import, modify, or test against the Vineyard campaign or its source conversation.
- Do not commit credentials, tokens, account identifiers, or private campaign material.

## Product default

- The game master's default model is GPT-6 Luna (`gpt-6-luna`). Keep Automatic available as an explicit operator choice; it follows the connected account's first listed model.
- API token prices do not describe usage charged against a ChatGPT plan. Do not promise that choosing Luna reduces a particular plan's allowance by a specific amount.
