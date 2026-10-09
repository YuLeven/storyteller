# Security

Storyteller is a locally hosted, single-player application. Campaigns and session history are stored in PostgreSQL on the host. ChatGPT OAuth credentials and the local signing key are stored outside the repository; see [Local development](docs/LOCAL_DEVELOPMENT.md). Campaign backups include session history and private GM context, so treat them as sensitive files.

Do not commit `.env` files, OAuth credentials, tokens, signing keys, database dumps, campaign backups, or private campaign data. If a secret is accidentally committed, revoke or rotate it first; deleting it from the working tree does not remove it from Git history.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository when it is available. If private reporting is unavailable, contact the repository maintainer through GitHub before sharing exploit details. Do not post credentials, private campaign content, or an exploitable reproduction in a public issue.

The local development server binds to loopback by default. Docker Compose publishes its port on all host interfaces; use it only on a trusted network unless you have added appropriate network protections. Do not expose a local instance or its campaign database to the public internet.
