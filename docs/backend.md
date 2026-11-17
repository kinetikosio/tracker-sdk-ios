# Your backend

[← Kinetikos Tracker SDK for iOS](../README.md)

Your server does three things for the SDK: it tells Kinetikos who takes part, it gives your app a token for each person, and it tells Kinetikos when someone stops. Full reference: the Kinetikos *Integration API* document.

**Keep the client credentials on your server.** Anything in an app can be extracted. Your app only ever holds participant tokens, which last eight hours and work for one person.

## Which backend

Kinetikos gives you a tenant (your own isolated space) and client credentials, with the `participants:write` and `participants:token` scopes, for each environment you use. A participant token works only on the backend that issued it, so your server and the SDK must use the same environment.

| Environment | Backend URL (`<host>` below) | In the SDK |
|---|---|---|
| Development | `https://tracker-api-dev.kinetikos.io` | `.development` |
| Staging | `https://tracker-api-stg.kinetikos.io` | `.staging` |
| Production | `https://tracker-api.kinetikos.io` | `.production` |

## 1. Get your server's token

```sh
curl -X POST https://<host>/v1/oauth/token \
  -u "$CLIENT_ID:$CLIENT_SECRET" \
  -d grant_type=client_credentials -d scope="participants:write participants:token"
```

Cache it until `expires_in` runs out.

## 2. Invite a participant

When someone in your system should be tracked (they joined a programme, a clinician enrolled them…), invite them by **your** id for them, the `external_id`:

```sh
curl -X POST https://<host>/v1/participants -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"external_id":"P-17"}'
```

Inviting the same `external_id` again is safe; it returns the existing invitation. Invite only the people who will actually be tracked.

## 3. Give your app participant tokens

Add an endpoint **on your server** that your app calls with the user's own session (your login). It checks who the user is, then asks Kinetikos for that person's token. The first token for an invited person also enrolls them.

```sh
curl -X POST https://<host>/v1/participant-tokens -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"external_id":"P-17"}'
```

```json
{ "access_token": "eyJhbGciOi...", "token_type": "Bearer", "expires_in": 28800, "participant": { "status": "enrolled", "…": "…" } }
```

- **Only hand a person's token to that person.** Kinetikos trusts your server to say who is who.
- Tokens last `expires_in` seconds (8 hours). Cache each person's token and fetch a new one shortly before it expires, not on every call. Revoking someone or suspending your institution takes effect at once, whatever token their phone holds.

When Kinetikos refuses:

| Answer | Meaning | What to do |
|---|---|---|
| `403 PARTICIPANT_REVOKED` | The person was revoked. | Don't return a token; your app should stop asking for a while. |
| `403 TENANT_INACTIVE` | Your institution is suspended or has ended the study. | Don't return a token (throw from `tokenProvider`). It works again as soon as the institution is active. |
| `404 NOT_FOUND` | Never invited. | Invite them first, if they should take part. |
| `409 ENROLLED_IN_APP` | The person enrolled in the Kinetikos app with their Enrollment Code. | Participant tokens are only for people who use the SDK. |
| `409 CONFLICT` (rare), `429 TOO_MANY_REQUESTS`, `503 SERVICE_UNAVAILABLE` | Temporary. `429` is your institution's limit: wait for `Retry-After`. | Retry later. Meanwhile return your cached token if it is still valid, or throw: the SDK keeps recording and uploads later. |

## 4. Revoke

When someone should stop being tracked: `POST /v1/participants/{id}/revoke`. Their phone stops recording and deletes what it hadn't sent the next time it talks to Kinetikos. To bring them back, invite them again: they keep their history, but must give consent again in your app.
