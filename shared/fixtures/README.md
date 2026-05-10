# Shared Golden Fixtures

Fixtures are stable examples used by HarmonyOS, iOS, Android, and server tests.

Rules:

- Keep fixtures small.
- Use valid IDs and payload shapes from `shared/contracts/openapi/happyword-api.openapi.json`.
- Do not include secrets, real tokens, real emails, or production family data.
- If a fixture represents an HTTP response, include status and headers when those affect client behavior.
