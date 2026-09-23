ipMagnetize
===========

This is a fork of [ipMagnet](https://github.com/cbdevnet/ipmagnet) - see the upstream repository
for what the project does, requirements, and manual (non-Docker) setup instructions.

This fork adds Docker packaging and an optional TLS reverse-proxy setup. The notes below cover
only what's specific to this fork; everything else (behavior, database schema, privacy notes,
timeout/interval feature, basic auth) is documented upstream.

## Running in Docker

A `Dockerfile` and `docker-compose.yml` are provided. The image is based on `php:8.2-apache` with the
`pdo_sqlite` extension enabled, and stores the SQLite database outside the web root at `/var/www/data`
so it can't be downloaded and so it persists across container recreation.

Quick start:

```
docker compose up -d --build
```

This starts ipMagnet on http://localhost/, with the database persisted in the `ipmagnet-data`
volume. Edit `TRACKER_URL` in `docker-compose.yml` to the public URL clients will use before deploying,
including the trailing slash.

Environment variables (applied at container start, no rebuild needed):

* `TRACKER_URL` - the public tracker URL embedded in generated magnet links (equivalent to editing line 2 of `index.php` upstream).
* `ENABLE_INTERVAL` - set to `true` to enable the tracker interval feature (see upstream warning about this).
* `TRACKER_INTERVAL` - the interval in seconds, if enabled.

Without Compose:

```
docker build -t ipmagnet .
docker run -d -p 80:80 -e TRACKER_URL="http://localhost/" -v ipmagnet-data:/var/www/data ipmagnet
```

### Optional: TLS via SWAG (reverse proxy)

`docker-compose.swag.yml` is an overlay that puts [linuxserver/swag](https://github.com/linuxserver/docker-swag)
(nginx + automatic Let's Encrypt certificates) in front of ipMagnet and removes ipMagnet's own
public port, so only swag is exposed on 80/443. It uses the Cloudflare DNS-01 challenge, so it
works even if the host isn't reachable on 80/443 during issuance and doesn't require pointing the
apex domain anywhere.

1. Create a Cloudflare API token scoped to your zone with **Zone:DNS:Edit** and **Zone:Zone:Read**
   permissions only.
2. Save it at `<SWAG_CONFIG_DIR>/dns-conf/cloudflare.ini` (default `./swag-config/dns-conf/cloudflare.ini`)
   as:
   ```
   dns_cloudflare_api_token = <token>
   ```
   and `chmod 600` it. Never commit this file.
3. Set `SWAG_URL` (your registered domain, e.g. `example.com`) and `SWAG_EMAIL` (for Let's Encrypt
   registration). Also set `IPMAGNET_BIND=127.0.0.1` and `IPMAGNET_PORT` to an unused local port
   (e.g. `8081`) so ipMagnet's own port isn't publicly reachable alongside swag's - Compose merges
   `ports` additively across `-f` files rather than letting an overlay replace it, so this can't be
   done from `docker-compose.swag.yml` itself. Then start both files together, including any
   deployment-specific override:
   ```
   docker compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.swag.yml up -d
   ```
4. Two ready-made proxy configs are provided in `swag-templates/`, matching linuxserver's own
   per-app sample convention - pick one (or both) and copy it into swag's persistent config volume,
   dropping the `.sample` suffix so nginx picks it up, then reload: `docker exec swag nginx -s reload`.

   * **Subdomain method** (`ipmagnet.subdomain.conf.sample` → `nginx/proxy-confs/ipmagnet.subdomain.conf`) -
     serves ipMagnet at `https://ipmagnet.<yourdomain>/`, as its own vhost. This is what the DNS
     record and Cloudflare token above are for, and needs no other changes.
   * **Subfolder method** (`ipmagnet.subfolder.conf.sample` → `nginx/proxy-confs/ipmagnet.subfolder.conf`) -
     serves ipMagnet at `https://<yourdomain>/ipmagnet/`, under swag's default site instead of a
     dedicated subdomain. Since that default site answers for whatever hostname(s) `URL`/
     `EXTRA_DOMAINS` cover, only use this if you actually want ipMagnet exposed under your bare
     apex domain (which may already be serving something else there) - and if `ONLY_SUBDOMAINS=true`,
     the cert won't cover the apex at all, so you'd need to unset that or add it via `EXTRA_DOMAINS`.

   **Note:** ipMagnet reads the client IP from `REMOTE_ADDR`, which under this proxy setup will be
   swag's internal container address rather than the real visitor - defeating the point of the app.
   See upstream's "Deployment behind a reverse proxy" notes for what needs to change in `index.php`
   to read the real client IP from the forwarded-for header instead.
