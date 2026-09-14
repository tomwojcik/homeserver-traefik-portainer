# homeserver-traefik-portainer

A complete homeserver setup using **Traefik reverse proxy** with **automatic HTTPS** and **Portainer** for easy container management. Torrenting runs inside a VPN kill switch. Everything is LAN-only by default; external access is opt-in.

## Features

✅ **Local-first architecture** - Fast streaming without internet dependencies  
✅ **Automatic HTTPS** - Set-and-forget SSL certificates via Let's Encrypt  
✅ **VPN-protected torrenting** - qBittorrent lives inside a Gluetun WireGuard kill switch  
✅ **Easy service deployment** - Deploy services via Portainer's web UI  
✅ **LAN-only by default** - Admin UIs are gated to private networks by Traefik; external access is opt-in  
✅ **Service auto-discovery** - Traefik automatically detects new services  
✅ **No port conflicts** - Everything routed through Traefik on 80/443  

## Quick Start

### 1. Configure Environment
```bash
cp .env.example .env
# Edit .env and configure:
# - SERVER_DOMAIN=example.com
# - ACME_EMAIL=your-email@example.com  
# - CF_DNS_API_TOKEN=your_cloudflare_dns_token
# (VPN credentials are entered in the Portainer form of the media-server template, not here)
```

#### Setting up Cloudflare DNS API Token

For automatic HTTPS certificates, you need a Cloudflare API token with DNS permissions:

1. **Buy a domain** - Cloudflare offers domains at cost (no markup) and provides excellent DNS management
2. **Create API Token**:
   - Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
   - Click "Create Token"
   - Use "Custom token" template
   - **Permissions**:
     - Zone:Zone:Read
     - Zone:DNS:Edit  
   - **Zone Resources**: 
     - Include: Specific zone: `your-domain.com`
   - **Client IP Address Filtering**: Leave empty (optional)
   - Click "Continue to summary" → "Create Token"
3. **Save the token** - You'll use this for `CF_DNS_API_TOKEN` in your `.env` file

**Alternative DNS Providers**: If not using Cloudflare, check Traefik's [supported ACME providers](https://doc.traefik.io/traefik/https/acme/#providers) and adjust the configuration accordingly.

### 2. Set Up DNS

#### Local DNS Configuration
Point `*.example.com` to your NAS IP address:
- **Router DNS**: Add wildcard DNS entry
- **Pi-hole**: Add local DNS record  
- **Hosts file**: `192.168.1.100 jellyfin.example.com` (etc.)

#### Cloudflare DNS Configuration
For external access and Let's Encrypt certificates:
1. **In Cloudflare Dashboard**: Go to your domain → DNS
2. **Add DNS Record**:
   - **Type**: `A`
   - **Name**: `*` (wildcard)
   - **IPv4 address**: Your NAS IP address (e.g., `192.168.1.100`)
   - **Proxy status**: ☁️ **Disabled** (DNS only, not proxied)
   - **TTL**: Auto
3. **Click Save**

**Important**: The proxy status must be disabled for Let's Encrypt DNS challenges to work properly.

### 3. Start Core Services
```bash
docker-compose up -d
```

This starts:
- **Traefik v3.0** (reverse proxy with automatic HTTPS)
- **Portainer 2.32.0** (container management)
- **Cloudflared** (optional; only used if you set up a Cloudflare Tunnel)

### 4. Deploy Services via Portainer

**IMPORTANT: Deploy in this order!**

1. **Access Portainer**: `https://portainer.example.com`
2. **Configure App Templates**:
   - Go to **Settings** > **App Templates**
   - Set URL: `https://raw.githubusercontent.com/tomwojcik/homeserver-traefik-portainer/master/template.json`
3. **Deploy "Complete Media Server with VPN"**: Gluetun is part of that stack. Read
   [stacks/media-server/readme.md](stacks/media-server/readme.md) first for the Synology
   prerequisites (TUN boot task, directory ownership).
4. **Deploy other services**: Any order

## Available Services

Deploy any of these through Portainer's App Templates:

### **Media & Entertainment**
- **Complete Media Server with VPN** - one stack: Gluetun + qBittorrent (VPN), Prowlarr + FlareSolverr,
  Sonarr, Radarr, Bazarr, Jellyfin, Seerr (Jellyseerr). See [stacks/media-server](stacks/media-server/readme.md)
- **MeTube** - YouTube downloader (not routed through the VPN)

### **Productivity**
- **Nextcloud** - File sync and collaboration
- **Vaultwarden** - Self-hosted password manager (Bitwarden-compatible)
- **Heimdall** - Dashboard for organizing services
- **Uptime Kuma** - Service monitoring

### **Development**
- **Gitea/Gogs** - Git repositories
- **Docker Registry** - Private container registry
- **n8n** - Workflow automation

### **Utilities**
- **Dozzle** - Container log viewer
- **CyberChef** - Data transformation tools
- **MinIO** - S3-compatible object storage

## Service URLs

After setup, your services will be available at:
- https://traefik.example.com (Traefik dashboard)
- https://portainer.example.com (Container management)
- https://jellyfin.example.com (Media streaming - **local speed**)
- https://sonarr.example.com (TV show management)
- https://qbittorrent.example.com (Torrents via VPN)
- https://metube.example.com (YouTube downloads)
- https://nextcloud.example.com (File sync)
- https://vaultwarden.example.com (Password manager)
- https://uptime.example.com (Service monitoring)

The media-server UIs are only reachable from private LAN ranges (Traefik `ipAllowList`, see
`LAN_CIDR` in the template). Containers talk to each other by container name
(`http://radarr:7878`), never through these public hostnames.

## Network Architecture

### **Local Access (Primary)**
```
Local Device → Router DNS → NAS:443 → Traefik → Service
```
**Benefits**: Full bandwidth, no internet dependency, lowest latency

### **External Access (Optional)**
None by default. If you publish a service through a Cloudflare Tunnel, remove the
`media-lan-only` middleware from that router; tunnel traffic reaches Traefik from the
Docker bridge and is otherwise rejected.

### **VPN Protection (Torrents)**
```
qbittorrent → Gluetun (WireGuard, kill switch) → Internet
prowlarr / *arr / metube → Internet directly
```
Only the torrent transfer is VPN'd. Indexer searches and YouTube downloads use the NAS IP.

## VPN Setup (Critical for Torrents)

Gluetun is a service inside the media-server stack (WireGuard only). Credentials go into the
template form (`VPN_SERVICE_PROVIDER`, `WIREGUARD_ADDRESSES`, `SERVER_COUNTRIES`) and the
private key either into the form or, preferably, into a root-only file on the NAS
(`/volume1/docker/media-server/gluetun/secrets/wireguard_private_key`).

### Verify the VPN
```bash
docker logs gluetun                          # look for "Wireguard setup is complete" and a healthy check
docker exec gluetun cat /tmp/gluetun/ip      # VPN server IP, not your real IP (the image has no curl)
docker stop gluetun                          # kill-switch test: qbittorrent must lose connectivity
```

### Accessing qBittorrent
`https://qbittorrent.<domain>` (LAN only). Sonarr and Radarr reach it as host `gluetun`,
port `8080`. Never publish port 8080 on the host: that bypasses Traefik, TLS and the LAN gate.

### Workflow after setup
1. **Request media**: Seerr → Sonarr/Radarr
2. **Automatic download**: Prowlarr finds it, qBittorrent downloads it through the VPN
3. **Import**: Sonarr/Radarr hardlink it into `/data/tv` or `/data/movies`, Bazarr adds subtitles
4. **Watch**: Jellyfin

## Adding New Services

### Method 1: Portainer App Templates (Recommended)
1. Deploy service through Portainer App Templates
2. Service automatically gets Traefik labels
3. Instantly available at `https://service.example.com`

### Method 2: External Repository
Perfect for deploying your own applications:

```yaml
services:
  my-app:
    build: .
    container_name: my-app
    networks:
      - homeserver
    restart: unless-stopped
    labels:
      - "my.zone=homeserver"
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${SERVER_DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=myresolver"
      - "traefik.http.services.myapp.loadbalancer.server.port=3000"

networks:
  homeserver:
    name: homeserver
    external: true
```
If your service talks to another container, use its container name (`http://sonarr:8989`),
not the public hostname.

### Method 3: Manual Stack Deployment
1. **In Portainer**: Stacks → Add Stack → Git Repository
2. **Enter your repo URL**: `https://github.com/yourusername/project`
3. **Add environment variables**: Include `SERVER_DOMAIN`
4. **Deploy**: Service available at `https://project.example.com`

## External Access Configuration

Nothing is published outside the LAN by default.

### Option 1: Cloudflare Tunnel (if you need it)
Run `cloudflared` from the root compose with a tunnel token and add public hostnames for the
services you want, origin `https://traefik:443`. For any media-server router you publish,
remove `media-lan-only` from its `traefik.http.routers.<name>.middlewares` label and put
Cloudflare Access in front of the hostname.

### Option 2: Port Forwarding
Not recommended: it exposes every routed hostname to the internet.

## Synology NAS Setup

Synology DSM uses ports 80 and 443 for its web interface, which conflicts with Traefik. Here's how to resolve this:

### Port Conflict Resolution
1. **Change DSM ports** (recommended approach):
   ```bash
   sed -i -e 's/80/81/' -e 's/443/444/' /usr/syno/share/nginx/server.mustache /usr/syno/share/nginx/DSM.mustache /usr/syno/share/nginx/WWWService.mustache
   ```

2. **Restart nginx service**:
   - **DSM < 7**: `synoservicecfg --restart nginx`
   - **DSM ≥ 7**: `sudo systemctl restart nginx`

3. **Access DSM**: Use `http://nas-ip:81` or `https://nas-ip:444` instead of default ports

### Alternative Approach
Instead of changing DSM ports, you can modify Traefik to use different ports in the docker-compose.yml:
```yaml
ports:
  - "8080:80"   # HTTP
  - "8443:443"  # HTTPS
```
Then access services via `https://service.example.com:8443`

## Troubleshooting

### **HTTPS Issues**
- **Check DNS**: Ensure `*.example.com` points to NAS IP
- **Check certificates**: `docker logs traefik`
- **Cloudflare API**: Verify `CF_DNS_API_TOKEN` is correct
- **Domain ownership**: Must control DNS for Let's Encrypt

### **VPN Issues**
- **Check gluetun logs**: `docker logs gluetun`
- **Verify credentials**: WireGuard keys must be valid
- **Test connection**: `docker exec gluetun cat /tmp/gluetun/ip`
- **Port forwarding**: Check if VPN supports it

### **Service Not Accessible**
- **Check Traefik dashboard**: `https://traefik.example.com`
- **Verify labels**: Service must have proper Traefik labels
- **Check networks**: Service must be on `homeserver` network
- **DNS cache**: Clear browser/system DNS cache

### **Portainer Security Timeout**
If Portainer shows "timeout.html" or security timeout message:
- **Cause**: Portainer requires admin setup within 2 minutes of first start
- **Fix**: 
  ```bash
  docker restart portainer
  # Immediately go to portainer.example.com and create admin user
  ```
- **Alternative**: Access directly via `http://nas-ip:9000` during setup
- **Note**: This only happens on first setup - once admin is created, normal access works

### **Published Ports Bypass Traefik**
A `ports:` mapping makes a service reachable at `nas-ip:port` in plain HTTP, outside Traefik,
TLS and the LAN gate. Keep ports unpublished in production; if a hostname returns 404, check
the router in the Traefik dashboard and the container's labels instead.

### **Performance Issues**
- **Local vs External**: Use local URLs for best performance
- **GPU transcoding**: enabled in media-server (Jellyfin gets the render node); see `stacks/media-server/known-issues.md`
- **Storage**: Ensure fast storage for media files

## Security Best Practices

### **Network Isolation**
- Torrent traffic only leaves through the Gluetun kill switch
- FlareSolverr (sandbox-less Chromium) sits on a stack-private network
- No host ports published by the media-server stack (only Traefik 80/443)

### **Access Control**
- Media-server UIs: LAN-only via Traefik `ipAllowList` (`LAN_CIDR`), security headers on every router
- Every app keeps its own login enabled; Seerr's login page is rate-limited
- External: nothing by default; opt-in per router (see External Access)

### **Containers**
- Images pinned to exact versions
- LinuxServer apps run as your user with a read-only root filesystem and no capabilities
- Memory and process limits, log rotation and health checks on every media-server service

### **Certificate Management**
- Automatic Let's Encrypt renewal
- Wildcard certificates for all subdomains
- DNS challenge (no port 80 requirement)

## Performance Optimization

### **Media Streaming**
- **Local access only**: No tunnel overhead
- **Direct file access**: Mount media directories properly
- **GPU acceleration**: on by default in the media-server stack (Intel QuickSync via the render node)

### **Resource Management**
- **Health checks**: every media-server service has one; `deunhealth` restarts qBittorrent when it loses gluetun's network
- **Resource limits**: memory and pids limits on every media-server service (scale down on a small NAS)
- **Monitoring**: Use cAdvisor and Uptime Kuma

## Deployment Order (Important!)

1. **Core services**: `docker-compose up -d` (Traefik + Portainer)
2. **Media server**: deploy "Complete Media Server with VPN" (Gluetun is inside it; qBittorrent waits for it)
3. **Other services**: Deploy in any order

## Contributing

This is a production-ready homeserver setup optimized for performance and security. If you find it useful:
- ⭐ Star the repository
- 🍴 Fork for your own modifications  
- 📝 Share improvements via issues/PRs

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Gluetun VPN Documentation](https://github.com/qdm12/gluetun)
- [Portainer Templates Format](https://docs.portainer.io/v/ce-2.11/advanced/app-templates/format)
- [Let's Encrypt + Cloudflare](https://doc.traefik.io/traefik/https/acme/#providers)
