# homeserver-traefik-portainer

A complete homeserver setup using **Cloudflare Tunnel** and **Portainer** for easy container management.

## Features

✅ **No port forwarding needed** - Cloudflare Tunnel handles everything  
✅ **Automatic HTTPS** - No more SSL certificate issues  
✅ **Easy service deployment** - Deploy services via Portainer's web UI  
✅ **Built-in DDoS protection** - Cloudflare shields your server  
✅ **Works behind NAT/firewall** - No network configuration needed  
✅ **Free for personal use** - Up to 50 subdomains with Cloudflare Tunnel  
✅ **No shell scripts** - Everything managed through web interfaces  

## Quick Start

### 1. Setup Cloudflare Tunnel
1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** > **Tunnels**
3. Click **Create a tunnel**, name it "homeserver-private"
4. Copy the tunnel token (this will be for your homeserver services)

### 2. Configure Environment
```bash
cp .env.example .env
# Edit .env and add:
# CLOUDFLARE_TUNNEL_TOKEN_PRIVATE=your_private_tunnel_token
```

### 3. Start Core Services
```bash
docker-compose up -d
```

This starts:
- **Portainer 2.32.0** (container management) - accessible at `http://server-ip:9000`
- **Cloudflared-Private** (tunnel for homeserver services with authentication)

### 4. Configure Tunnel Routes in Cloudflare

In the Cloudflare Zero Trust dashboard, add these public hostnames:

| Service | Subdomain | Service URL |
|---------|-----------|-------------|
| Portainer | `portainer` | `http://portainer:9000` |
| Dozzle | `dozzle` | `http://dozzle:8080` |
| Heimdall | `heimdall` | `http://heimdall:80` |
| CyberChef | `cyberchef` | `http://cyberchef:8000` |

### 5. Deploy Services via Portainer

1. Access Portainer at `https://portainer.yourdomain.com`
2. Go to **Settings** > **App Templates**
3. Set template URL: `https://raw.githubusercontent.com/tomwojcik/homeserver-traefik-portainer/master/template.json`
4. Go to **App Templates** and deploy any service
5. After deploying, add the corresponding route in Cloudflare Dashboard

## Available Services

Deploy any of these through Portainer's App Templates:

- **Dashboard**: Heimdall (landing page)
- **Monitoring**: Dozzle (logs), Uptime Kuma, cAdvisor (resources)
- **Media**: MeTube (YouTube downloader), TubeSync (YouTube PVR)
- **Storage**: Nextcloud, MinIO (S3-compatible)
- **Development**: Gogs (Git), PyPI Server, Docker Registry
- **Tools**: CyberChef, n8n (automation)

## Service URLs

After setup, your services will be available at:
- https://portainer.yourdomain.com
- https://dozzle.yourdomain.com  
- https://heimdall.yourdomain.com
- https://metube.yourdomain.com
- etc.

## Adding New Services

### Method 1: Using App Templates (Predefined Services)
1. Deploy service through Portainer App Templates
2. In Cloudflare Zero Trust, add new public hostname
3. Point it to `http://service-name:port`
4. Service instantly available at `https://service.yourdomain.com`

### Method 2: External Repository (Side Projects)
Perfect for deploying your own applications or projects from GitHub:

1. **In Portainer**: Go to **Stacks** → **Add Stack** → **Repository**
2. **Enter your GitHub repo URL**: `https://github.com/yourusername/your-project`
3. **Specify docker-compose.yml path** (if not in root)
4. **Deploy the stack**
5. **Choose the appropriate tunnel**:
   - **Private projects** → Use `homeserver` network → Route via private tunnel
   - **Public projects** → Use `public-projects` network → Route via public tunnel

**For Private Projects (requires auth):**
```yaml
version: "3.8"
services:
  my-private-app:
    build: .
    container_name: my-private-app
    networks:
      - homeserver  # Routes through private tunnel
    restart: unless-stopped

networks:
  homeserver:
    name: homeserver
    external: true
```

**For Public Projects (with their own tunnel):**
```yaml
version: "3.8"
services:
  # Your public application
  my-public-app:
    build: .
    container_name: my-public-app
    restart: unless-stopped

  # Each public project manages its own tunnel
  cloudflared:
    image: cloudflare/cloudflared:2024.6.1
    container_name: my-project-tunnel
    restart: always
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
    security_opt:
      - no-new-privileges:true
    read_only: true
    user: "65532:65532"
```

**Benefits of separate tunnels per project:**
- Each project is completely isolated
- Independent deployment and management
- Different authentication/access policies per project
- No shared infrastructure dependencies

**📁 See complete example**: Check the `examples/public-side-project/` directory for a working example with whoami service and dedicated tunnel.

### Method 3: Configure Authentication
**Set up Cloudflare Access for Private Services:**
1. Go to **Zero Trust** → **Access** → **Applications**
2. Click **Add an application** → **Self-hosted**
3. Set application domain: `*.yourdomain.com` (or specific subdomain)
4. Add policy: **Allow** → **Emails** → Add your email addresses
5. Now all homeserver services require email authentication!

**Public tunnel services bypass authentication automatically.**

## Network Architecture

```
Internet → Cloudflare → Tunnel → Docker Network (homeserver) → Services
```

All services communicate through the `homeserver` Docker network.


## Troubleshooting

**Tunnel not connecting?**
- Check tunnel token is correct
- Verify cloudflared container is running: `docker logs cloudflared`

**Service not accessible?**
- Ensure service is on `homeserver` network
- Check service is running: `docker ps`
- Verify Cloudflare route points to correct `http://container:port`

**Need direct access?**
- Portainer always available at `http://server-ip:9000`
- Other services available on their internal ports within the Docker network

## References

- [Portainer Templates Documentation](https://docs.portainer.io/v/ce-2.11/advanced/app-templates/format#container-template-definition-format)
- [Default Portainer Templates](https://github.com/portainer/templates/blob/master/templates-2.0.json)
- [Community Templates](https://github.com/Qballjos/portainer_templates/blob/master/Template/template.json)

## Contributing

This is my personal homeserver setup. If it works for me, there's nothing to improve.
Feel free to star/fork/download - I hope it makes your life easier!
