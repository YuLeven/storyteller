# Guidance for coding agents

## Protect the owner's model allowance

- Development and automated tests should use deterministic fake providers by default. The owner has authorized focused live gameplay tests through the actual ChatGPT-plan API using `gpt-6-luna` at low reasoning effort when real provider behavior or story quality needs verification.
- Do not use Sol, Astra, or another more expensive model unless the owner explicitly requests that specific comparison. This authorization is not permission for model comparisons.
- Keep live runs small and purposeful; avoid redundant requests. Record live usage and never treat a fake-provider test as evidence of live model behavior.

## Campaign and data boundaries

- Run Elixir commands in WSL and use the isolated test database for development checks.
- Use independently authored fictional campaigns such as Quiet Observatory for any authorized live gameplay exploration. Never access, import, modify, or test against the Vineyard campaign or its source conversation.
- Do not commit credentials, tokens, account identifiers, or private campaign material.

## Product default

- The game master's default model is GPT-6 Luna (`gpt-6-luna`). Keep Automatic available as an explicit operator choice; it follows the connected account's first listed model.
- API token prices do not describe usage charged against a ChatGPT plan. Do not promise that choosing Luna reduces a particular plan's allowance by a specific amount.
