# Example Public Side Project

This is an example of how to deploy a public side project with its own Cloudflare Tunnel.

## What's Included

- **whoami service**: Simple HTTP service that returns request information
- **Cloudflare Tunnel**: Dedicated tunnel for this project (no authentication required)
- **Security hardening**: Read-only filesystems, resource limits, health checks

## Setup Steps

### 1. Create Cloudflare Tunnel
1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** → **Tunnels**
3. Click **Create a tunnel**, name it "my-public-project"
4. Copy the tunnel token

### 2. Configure Environment
```bash
cp .env.example .env
# Edit .env and add your tunnel token
```

### 3. Deploy
```bash
docker-compose up -d
```

### 4. Configure Public Hostname
1. In Cloudflare Zero Trust dashboard, go to your tunnel
2. Add **Public Hostname**:
   - **Subdomain**: `my-project` (or whatever you want)
   - **Domain**: `yourdomain.com`
   - **Service**: `http://whoami:80`

### 5. Access Your Project
Visit `https://my-project.yourdomain.com` - no authentication required!

## Customization

Replace the `whoami` service with your actual application:

```yaml
my-app:
  build: .
  # or: image: your-app:latest
  container_name: my-public-app
  restart: unless-stopped
  # Add your app configuration here
```

## Benefits of This Approach

✅ **Complete isolation** from homeserver infrastructure  
✅ **Independent deployment** and updates  
✅ **No authentication** required (public access)  
✅ **Own tunnel** with separate configuration  
✅ **Security hardened** with best practices  
✅ **Resource limited** to prevent resource exhaustion  

## Security Features

- Non-root user execution
- Read-only filesystem
- No new privileges
- Resource limits (CPU/memory)
- Health checks for monitoring
- Minimal attack surface