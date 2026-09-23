ipMagnetize
===========

ipMagnetize is a fork of [ipMagnet](https://github.com/cbdevnet/ipmagnet), which shows which IP
addresses your BitTorrent client hands out to trackers. See upstream for what the app does, its
privacy notes, and manual (non-Docker) setup. The app itself still calls itself ipMagnet.

This fork adds:

* A Docker image configured through environment variables.
* An optional HTTPS setup using [SWAG](https://github.com/linuxserver/docker-swag) with Let's Encrypt
  certificates.
* Correct client IP detection behind a reverse proxy (`TRUST_PROXY`).

**DISCLOSURE**: This code was written with the assistance of Claude Code (Anthropic).

## Quick start

From a checkout of this repository:

```bash
docker compose up -d --build
```

ipMagnet is now on http://localhost/. Before exposing it publicly, set `TRACKER_URL` to the address
BitTorrent clients will reach it at (see [Configuration](#configuration)), or the magnet links it
generates will point clients at `localhost`.

## Configuration

### Settings

| Variable | Default | Set in | Purpose |
|---|---|---|---|
| `TRACKER_URL` | `http://localhost/` | override file | Public URL of this instance, with trailing slash. Embedded in magnet links as the tracker. |
| `ENABLE_INTERVAL` | `false` | override file | Ask clients to re-announce periodically. Read upstream's warning before enabling. |
| `TRACKER_INTERVAL` | `300` | override file | Re-announce interval in seconds, if enabled. |
| `TRUST_PROXY` | `false` | override file | Take the client IP from a reverse proxy's `X-Real-IP` header. The SWAG overlay sets this to `true`. See [Behind another reverse proxy](#behind-another-reverse-proxy). |
| `IPMAGNET_BIND` | `0.0.0.0` | `.env` | Host address ipMagnet's port is published on. |
| `IPMAGNET_PORT` | `80` | `.env` | Host port ipMagnet is published on. |
| `IPMAGNET_MEM_LIMIT` | `256m` | `.env` | Memory cap for the ipMagnet container. It idles around 20 MB. |
| `SWAG_URL` | *(required for SWAG)* | `.env` | Your registered domain, e.g. `example.com`. |
| `SWAG_EMAIL` | *(required for SWAG)* | `.env` | Contact address for Let's Encrypt. |
| `SWAG_TZ` | `Etc/UTC` | `.env` | Time zone for the SWAG container. |
| `SWAG_CONFIG_DIR` | `./swag-config` | `.env` | SWAG's persistent config: certificates, nginx config, and the Cloudflare token. |
| `SWAG_MEM_LIMIT` | `512m` | `.env` | Memory cap for the SWAG container. Raise it if SWAG also serves other apps. |
| `SWAG_VERSION` | `5.8.0-ls486` | `.env` | SWAG image tag. See [Updating](#updating). |

If `TRACKER_URL` contains `"`, `$`, `\` or `#`, or `TRACKER_INTERVAL` isn't a whole number, the
container refuses to start. Run `docker compose logs ipmagnet` to see why.

### Where to put your settings

Don't edit `docker-compose.yml`. Your changes would conflict with (or be overwritten by) the next
`git pull`. Use these two files instead. Both are ignored by git.

* **`docker-compose.override.yml`** holds the container settings (`TRACKER_URL` and the others marked
  "override file" above):

  ```yaml
  services:
    ipmagnet:
      environment:
        TRACKER_URL: "https://ipmagnet.example.com/"
  ```

  A plain `docker compose` command loads this file automatically. If you list compose files yourself
  with `-f` or `COMPOSE_FILE`, include it in the list.

* **`.env`** holds the variables Compose itself reads (the ones marked `.env` above), one
  `NAME=value` per line. Compose reads it from the project directory.

## Running without Compose

```bash
docker build -t ipmagnet .
docker run -d -p 80:80 \
  -e TRACKER_URL="https://ipmagnet.example.com/" \
  -v ipmagnet-data:/var/www/data \
  ipmagnet
```

## HTTPS with SWAG (optional)

`docker-compose.swag.yml` adds SWAG (nginx with automatic Let's Encrypt certificates) in front of
ipMagnet on ports 80 and 443, and sets `TRUST_PROXY=true` on ipMagnet. Certificates are issued through
Cloudflare's DNS-01 challenge, so the host doesn't need to be reachable during issuance.

**Already running SWAG?** Skip the overlay. Copy one of the templates from `swag-templates/` into your
existing SWAG's `nginx/proxy-confs/`, put ipMagnet on the same Docker network as SWAG so the hostname
`ipmagnet` resolves, and set `TRUST_PROXY=true`.

### Prerequisites

* Your domain's DNS is hosted on Cloudflare.
* An `A` record (plus `AAAA` if the host has IPv6) for `ipmagnet.<your domain>` pointing at the host,
  set to **DNS only**. If Cloudflare proxies the record, every hit is logged with a Cloudflare address.
* A Cloudflare API token with only **Zone:DNS:Edit** and **Zone:Zone:Read**, scoped to that one zone.

### Setup

1. Save the token where SWAG will look for it:

   ```bash
   mkdir -p swag-config/dns-conf
   echo "dns_cloudflare_api_token = <token>" > swag-config/dns-conf/cloudflare.ini
   chmod 600 swag-config/dns-conf/cloudflare.ini
   ```

2. Create `.env`:

   ```ini
   SWAG_URL=example.com
   SWAG_EMAIL=you@example.com
   IPMAGNET_BIND=127.0.0.1
   IPMAGNET_PORT=8081
   COMPOSE_FILE=docker-compose.yml:docker-compose.override.yml:docker-compose.swag.yml
   ```

   * `IPMAGNET_BIND=127.0.0.1` keeps ipMagnet's own port off the public interface, so only SWAG is
     reachable. The overlay can't do this itself: Compose adds up `ports` entries across files
     instead of replacing them.
   * `COMPOSE_FILE` makes plain `docker compose` commands use all three files. The commands below
     assume it's set. On Windows, separate the files with `;` instead of `:`.

3. Create `docker-compose.override.yml` with an **https** tracker URL:

   ```yaml
   services:
     ipmagnet:
       environment:
         TRACKER_URL: "https://ipmagnet.example.com/"
   ```

   SWAG redirects all plain HTTP to HTTPS, and not every BitTorrent client follows redirects when
   announcing, so an `http://` tracker URL can lose hits.

4. Start everything, then watch SWAG obtain its certificate. Wait for `Server ready`:

   ```bash
   docker compose up -d --build
   docker compose logs -f swag
   ```

5. Install the proxy config and reload nginx. `swag-config/nginx/` only exists after SWAG's first
   start, which is why this comes last:

   ```bash
   cp swag-templates/ipmagnet.subdomain.conf.sample swag-config/nginx/proxy-confs/ipmagnet.subdomain.conf
   docker compose exec swag nginx -s reload
   ```

Open `https://ipmagnet.<your domain>/`. The page should show your public IP as "the address you've
accessed this page with". A `172.x.x.x` address means `TRUST_PROXY` isn't in effect.

### Subdomain or subfolder

Pick one. `TRACKER_URL` can only point at one of them.

* **Subdomain** (`ipmagnet.subdomain.conf.sample`) serves `https://ipmagnet.<your domain>/`. The
  overlay is set up for this. The subdomain name is fixed to `ipmagnet`. To change it, edit
  `SUBDOMAINS` in `docker-compose.swag.yml` and `server_name` in the proxy config.
* **Subfolder** (`ipmagnet.subfolder.conf.sample`) serves `https://<your domain>/ipmagnet/` from
  SWAG's default site. The certificate then has to cover your bare domain: set `ONLY_SUBDOMAINS=false`
  in `docker-compose.swag.yml`, and point the bare domain's DNS at this host. That moves anything
  currently served there. Set `TRACKER_URL` to `https://<your domain>/ipmagnet/`.

With a subdomain, SWAG's default site still answers requests for the host's bare IP, or any other
hostname, with a placeholder page. To close those connections without a reply, add `return 444;`
inside the `listen 443 ssl default_server` block of `swag-config/nginx/site-confs/default.conf` and
reload nginx. Skip this if you use the subfolder setup, or anything else on this SWAG uses subfolder
configs: they're served from that default site.

## Behind another reverse proxy

Set `TRUST_PROXY=true` only if ipMagnet can be reached **solely** through your proxy. The proxy must
set `X-Real-IP` to the client's address and overwrite any value the client sent. In nginx:
`proxy_set_header X-Real-IP $remote_addr;`.

ipMagnet uses the header only when all of these hold:

* `TRUST_PROXY` is `true`.
* The connection comes from a private or loopback address.
* The header contains a valid IP address.

Otherwise it logs the connecting address. `X-Forwarded-For` is ignored, because clients can prepend
fake entries to it. That differs from upstream's reverse-proxy advice, which doesn't apply to this fork.

## Firewalls

Host firewalls such as UFW and firewalld don't filter ports that Docker publishes. Docker inserts its
own iptables rules ahead of theirs, so `ufw status` can list only SSH while ipMagnet's port 80, or
SWAG's 80 and 443, are open to the internet. To restrict them, either:

* Use a firewall in front of the host, such as a DigitalOcean Cloud Firewall or an AWS security group.
  Docker can't bypass it.
* Add rules to Docker's `DOCKER-USER` iptables chain, which Docker checks before its own rules.

With the SWAG setup, `IPMAGNET_BIND=127.0.0.1` keeps ipMagnet's own port off the network whatever
the firewall rules are.

## Updating

```bash
git pull
docker compose build --pull
docker compose up -d
```

The app's code is built into the image, so restarting without rebuilding keeps running the old
version. `--pull` also fetches the newest `php:8.4-apache` base image, which is how PHP and Debian
security fixes reach the container, so run these regularly even when there's nothing to pull from
git. Your `.env` and override file aren't touched by `git pull`.

SWAG is pinned to a tested release, so it only changes when this repository moves the pin (picked up
by the commands above) or when you set `SWAG_VERSION` in `.env` to a tag from
[SWAG's releases](https://github.com/linuxserver/docker-swag/releases) and run `docker compose up -d`.

## Data and backups

Hits are stored in SQLite at `/var/www/data/ipmagnet.db3`, in the `ipmagnet-data` volume. To copy it
out:

```bash
docker compose cp ipmagnet:/var/www/data/ipmagnet.db3 ./ipmagnet-backup.db3
```

You can bind-mount a host directory at `/var/www/data` instead. The container fixes its ownership at
startup. For users' privacy, upstream recommends wiping the database regularly.
