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
