# Complete Media Server Stack

A comprehensive media server setup with VPN-protected downloading, automated media management, and streaming.

## What's Included

### Download & VPN
- **Gluetun**: VPN gateway for secure torrenting
- **qBittorrent**: Torrent client (routed through VPN)

### Media Management
- **Prowlarr**: Indexer manager (manages trackers)
- **Sonarr**: TV show manager
- **Radarr**: Movie manager
- **Bazarr**: Subtitle manager

### Media Server
- **Jellyfin**: Open-source media server

### Request Management
- **Jellyseerr**: User-friendly request interface for movies/TV shows

## Setup Requirements

### 1. VPN Configuration
You'll need VPN credentials from a supported provider:
- Surfshark, NordVPN, ExpressVPN, etc.
- WireGuard private key and addresses
- Or OpenVPN credentials

## Post-Deployment Configuration

### 1. Initial Setup Order
1. **Prowlarr**: Configure indexers/trackers
2. **Sonarr/Radarr**: Link to Prowlarr and download clients
3. **Jellyfin**: Scan media libraries
4. **Jellyseerr**: Connect to Jellyfin and Sonarr/Radarr

### 2. Directory Structure
The stack creates these volumes:
- `media_data`: Shared media storage (movies, TV shows)
- `media_downloads`: Download staging area
- Individual config volumes for each service

### 3. VPN Security
- qBittorrent traffic is routed through Gluetun VPN
- If VPN disconnects, torrenting stops automatically
- Other services (streaming, management) use direct connection

## Hardware Acceleration

For GPU transcoding, uncomment the device sections:
```yaml
devices:
  - /dev/dri:/dev/dri  # Intel/AMD GPU
```

## Security Features

- All torrenting through VPN gateway
- No-new-privileges security option on all containers
- Isolated Docker network
- Volume-based storage (not host paths)

## Default Credentials

Most services don't require initial passwords, but you should set them up during first-time configuration through their web interfaces.