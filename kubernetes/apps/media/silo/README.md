# Silo

## Autoscan from Sonarr/Radarr

Silo scans newly imported files as soon as Sonarr or Radarr finishes an import. This is runtime
configuration stored in the Silo database and in the Sonarr/Radarr databases, not in Git. Recreate
it by hand after rebuilding any of them.

### Silo (Admin → Settings → Autoscan)

- Autoscan: enabled
- Source `Sonarr`: type *Sonarr/Radarr Webhook*, provider Sonarr, path mapping `/media/tv` → `/media/tv`
- Source `Radarr`: type *Sonarr/Radarr Webhook*, provider Radarr, path mapping `/media/movies` → `/media/movies`

Each source issues its own webhook URL with a secret token. Rotating it in Silo breaks delivery
until the new URL is pasted into Sonarr/Radarr.

### Sonarr / Radarr (Settings → Connect → Webhook)

- Name: `silo-autoscan`
- URL: `http://silo-app.media.svc.cluster.local:8080/api/v2/autoscan/webhooks/<token>`, built from the
  token of the matching Silo source; use this in-cluster host, not the public one
- Method: POST
- Triggers: On Import, On Upgrade, On Import Complete (Sonarr only), On Rename, and the delete events

Silo's library paths match Sonarr's and Radarr's root folders, so the path mappings don't change
anything. Silo still requires at least one mapping per source, otherwise deliveries match no library.

### Admin API

Every setting above is also available on the admin API (`/api/v2/admin/autoscan/{settings,sources}`,
`POST /api/v2/admin/autoscan/sources/{id}/webhook` to issue the URL). Authenticate with
`Authorization: Bearer $SILO_ADMIN_API_KEY` from the `silo-node-registration` secret.

## Requests through Seerr

Silo sends approved requests to Seerr, which passes them on to Sonarr and Radarr with its own
profiles and root folders. Like autoscan, this lives in the Silo database, not in Git.

- Admin → Plugins: the *Approved community* catalog is enabled (`include_approved_community_plugins`),
  with **Seerr Requests** (`silo.requests.seerr`) installed from it. No Silo-maintained plugin can
  route requests.
- Admin → Settings → Requests → Integrations: `Seerr`
  - URL: `http://seerr.media.svc.cluster.local`
  - API key: Seerr's API key (Settings → General in Seerr). Rotating it in Seerr breaks requests
    until it is updated here.
  - Attribute requests to: *Admin user*. Approval already happens in Silo, so every request reaches
    Seerr as the API-key owner and is auto-approved there.
  - Auto-approve: on. 4K: off, because Seerr has no 4K servers.
- Routing: *standard*. Movies and series go to `Seerr` for HD, and no advanced routes are set.
- Request settings: enabled, 5 requests per user per 7 days, manual approval, watchlist requests on.

Request endpoints are under `/api/v2/admin/request-{settings,integrations,routes,routing}`. Updates
need the `ETag` from a prior GET in an `If-Match` header.
