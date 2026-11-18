# MCP and outgoing UPI rollout

Apply the Prisma migrations before activating integration flags. Rehearse on a disposable PostgreSQL instance and use a separate staging origin and Auth0 tenant. Keep the legacy sync capability flag at its current setting until the supported older clients have drained their queues.

## MCP

- Create an Auth0 custom API with the exact HTTPS `MCP_URL` as the identifier, including `/api/mcp`. Enable RFC 8707 resource-parameter compatibility. Use RS256 and define `ledger:read` and `ledger:write`.
- Create a separate confidential web application for FinTrack identity linking. Its callback is `https://<fintrack-host>/api/v1/mcp/link/callback`. Configure `MCP_ISSUER`, `MCP_LINK_CLIENT_ID`, `MCP_LINK_CLIENT_SECRET`, and an independent `MCP_STATE_KEY`.
- Register the ChatGPT and Claude connector clients using their supported registration and callback methods. Add the actual OAuth client IDs to `MCP_ALLOWED_CLIENTS`. The connector token must carry the registered client identity, a resource audience, and requested ledger scopes. Enable refresh tokens only if needed by the client and supported by the issuer configuration.
- Enable `MCP_READ_ENABLED` in staging. In FinTrack Settings, link the Auth0 identity, then grant the connector read access. Check discovery at `/.well-known/oauth-protected-resource/api/mcp`, run tool discovery in both clients, and confirm revocation denies new calls. Turn on `MCP_WRITE_ENABLED` and approve write permission only for the limited pilot. After changing scopes, reconnect if the client needs a new access token.
- Set `FINTRACK_OPERATOR_IDS` only for designated FinTrack operator accounts to enable the aggregate-only health endpoint at `/api/v1/operations/health`.

## Outgoing UPI

- Generate an independent random 32-byte hex `UPI_DATA_KEY` and keep it stable across deployments. Enable `UPI_HANDOFF_ENABLED` for the pilot server. Build Android with `--dart-define=FINTRACK_UPI_PILOT=true` and point it at that server. Payments are initiated in Android. Web Settings links to history and statement matching.
- Test representative fixed, open, and signed/opaque QR codes in compatible installed UPI apps before wider release. Validate payer cancellation, return with no result, interrupted network, and manual reconciliation. The app does not need access to UPI credentials. A callback is advisory. Uploaded statements and manual entries are user-provided evidence.
- The statement preview supports a normalized UTF-8 CSV with the header `date,amount,direction,reference`, ISO dates, INR decimal amounts, and `debit` or `credit`. It proposes candidate payment attempts for debit rows. The owner explicitly confirms a match and either creates an expense or links an existing one. References from this flow are used for matching and deduplication.
- Automatic verification requires a partner that can verify these outgoing debits. Enable provider verification only after staging proves authoritative matching, event replay, and reversals.

## Account emails

Set a verified Resend sender in `ACCOUNT_EMAIL_FROM`, an API key in `RESEND_API_KEY`, and the canonical HTTPS `AUTH_URL`. Enable `ACCOUNT_VERIFICATION_ENABLED` after testing both email change and recovery delivery in staging. Password reset revokes mobile sessions, web session tokens, and connector grants.
