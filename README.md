# homeserver-traefik-portainer

A complete homeserver setup using **Traefik reverse proxy** with **automatic HTTPS** and **Portainer** for easy container management. Features VPN-protected downloading and both local and external access options.

## Features

✅ **Local-first architecture** - Fast streaming without internet dependencies  
✅ **Automatic HTTPS** - Set-and-forget SSL certificates via Let's Encrypt  
✅ **VPN-protected downloads** - Secure torrenting through isolated VPN container  
✅ **Easy service deployment** - Deploy services via Portainer's web UI  
✅ **Hybrid access** - Local network speed + selective external access  
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
# - VPN credentials for downloading services
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
- **Cloudflared** (selective external access)

### 4. Deploy Services via Portainer

**IMPORTANT: Deploy in this order!**

1. **Access Portainer**: `https://portainer.example.com`
2. **Configure App Templates**:
   - Go to **Settings** > **App Templates**
   - Set URL: `https://raw.githubusercontent.com/tomwojcik/homeserver-traefik-portainer/master/template.json`
3. **Deploy VPN stack FIRST**: Deploy "Gluetun VPN" 
4. **Deploy download services**: Deploy metube, media-server (depend on gluetun)
5. **Deploy other services**: Any order

## Available Services

Deploy any of these through Portainer's App Templates:

### **Media & Entertainment**
- **Jellyfin/Plex** - Media streaming servers
- **Sonarr/Radarr** - TV show/movie management  
- **Jellyseerr** - Media request system
- **MeTube** - YouTube downloader (VPN-protected)
- **qbittorrent** - Torrent client (VPN-protected)

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
- https://metube.example.com (YouTube downloads via VPN)
- https://nextcloud.example.com (File sync)
- https://vaultwarden.example.com (Password manager)
- https://uptime.example.com (Service monitoring)

## Network Architecture

### **Local Access (Primary)**
```
Local Device → Router DNS → NAS:443 → Traefik → Service
```
**Benefits**: Full bandwidth, no internet dependency, lowest latency

### **External Access (Selective)**
```
External → Cloudflare Tunnel → Specific Services
```
**Use for**: Nextcloud (file sync), Jellyseerr (remote requests)

### **VPN Protection (Downloads)**
```
qbittorrent/metube → Gluetun VPN → Internet
```
**Benefits**: IP masking, geographic flexibility, ISP protection

## VPN Setup (Critical for Downloads)

### 1. Deploy Gluetun Stack First
1. In Portainer App Templates, deploy "Gluetun VPN"
2. Configure your VPN credentials:
   - `VPN_SERVICE_PROVIDER` (surfshark, nordvpn, etc.)
   - `WIREGUARD_PRIVATE_KEY`
   - `WIREGUARD_ADDRESSES`

### 2. Verify VPN Connection
- Check gluetun logs: `docker logs gluetun`
- Test IP: `docker exec gluetun curl ifconfig.me`
- Should show VPN server IP, not your real IP

### 3. Deploy Download Services
- **metube**: Regular deployment (no VPN needed for YouTube downloads)
- **qbittorrent**: Routes through gluetun VPN for security

### 4. Access VPN-Protected Services

**qBittorrent Access (Setup Only)**
- **Normal operation**: No direct access needed - Sonarr/Radarr communicate automatically
- **Initial setup**: Temporarily expose port in gluetun stack:
  ```yaml
  # Add to gluetun service temporarily
  ports:
    - "8080:8080"  # Remove after setup complete
  ```
- **After setup**: Remove port exposure for maximum security
- **Troubleshooting**: Re-add port temporarily when needed

**Workflow After Setup:**
1. **Request media**: Jellyseerr → Sonarr/Radarr  
2. **Automatic download**: *arr stack → qBittorrent (via VPN)
3. **Watch content**: Jellyfin/Plex (local network speed)
4. **Zero manual intervention**: qBittorrent operates invisibly through VPN

## Adding New Services

### Method 1: Portainer App Templates (Recommended)
1. Deploy service through Portainer App Templates
2. Service automatically gets Traefik labels
3. Instantly available at `https://service.example.com`

### Method 2: External Repository
Perfect for deploying your own applications:

```yaml
version: "3.8"
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

### Method 3: Manual Stack Deployment
1. **In Portainer**: Stacks → Add Stack → Git Repository
2. **Enter your repo URL**: `https://github.com/yourusername/project`
3. **Add environment variables**: Include `SERVER_DOMAIN`
4. **Deploy**: Service available at `https://project.example.com`

## External Access Configuration

### Option 1: Cloudflare Tunnels (Secure)
Configure tunnels for services needing external access:
1. **Nextcloud**: File sync from anywhere
2. **Jellyseerr**: Remote media requests  
3. **Uptime Kuma**: Service monitoring

### Option 2: Port Forwarding (Basic)
Forward ports 80/443 to your NAS:
- **Pros**: Simple setup
- **Cons**: Synology nginx port conflicts, security risks

**Recommendation**: Use Cloudflare Tunnels for security

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
- **Test connection**: `docker exec gluetun curl ifconfig.me`
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

### **Services Not Routing Through Traefik**
**Important**: If a service has exposed ports in docker-compose (e.g., `ports: - "9000:9000"`), it will bypass Traefik routing:

- **Problem**: `portainer.example.com` returns 404, but `nas-ip:9000` works
- **Cause**: Exposed ports take precedence over Traefik routing
- **Solution**: 
  1. **For initial setup**: Temporarily expose ports, access via `nas-ip:port`
  2. **For production**: Comment out port mappings to force Traefik routing
  ```yaml
  # ports:
  #   - "9000:9000"  # Disable for Traefik routing
  ```
- **When to expose ports**: Only for troubleshooting or when Traefik fails

### **Performance Issues**
- **Local vs External**: Use local URLs for best performance
- **GPU transcoding**: Uncomment device mappings in media services
- **Storage**: Ensure fast storage for media files

## Security Best Practices

### **Network Isolation**
- Downloads isolated in VPN container
- Services communicate only through defined networks
- No direct port exposure (except Traefik 80/443)

### **Access Control**
- Local network: Full access to all services
- External: Only selected services via Cloudflare
- Authentication: Cloudflare Access for sensitive services

### **Certificate Management**
- Automatic Let's Encrypt renewal
- Wildcard certificates for all subdomains
- DNS challenge (no port 80 requirement)

## Performance Optimization

### **Media Streaming**
- **Local access only**: No tunnel overhead
- **Direct file access**: Mount media directories properly
- **GPU acceleration**: Enable for transcoding if available

### **Resource Management**
- **Health checks**: Services restart automatically
- **Resource limits**: Configured for containers
- **Monitoring**: Use cAdvisor and Uptime Kuma

## Deployment Order (Important!)

1. **Core services**: `docker-compose up -d` (Traefik + Portainer)
2. **VPN stack**: Deploy gluetun via Portainer (for qBittorrent only)
3. **Download services**: 
   - Deploy metube (standalone - no VPN needed)
   - Deploy media-server (qBittorrent uses gluetun VPN)
4. **Other services**: Deploy in any order

**Important**: Only qBittorrent requires VPN deployment order - metube can be deployed anytime

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
