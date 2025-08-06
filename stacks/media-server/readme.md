# Complete Media Server Stack

A comprehensive media server setup with VPN-protected downloading, automated media management, and multiple streaming options.

## What's Included

### Download & VPN
- **Gluetun**: VPN gateway for secure torrenting
- **qBittorrent**: Torrent client (routed through VPN)
- **SABnzbd**: Usenet downloader

### Media Management
- **Prowlarr**: Indexer manager (manages trackers/newsgroups)
- **Sonarr**: TV show manager 
- **Radarr**: Movie manager
- **Bazarr**: Subtitle manager

### Media Servers
- **Jellyfin**: Open-source media server
- **Plex**: Popular media server with premium features

### Request Management  
- **Jellyseerr**: User-friendly request interface for movies/TV shows

## Setup Requirements

### 1. VPN Configuration
You'll need VPN credentials from a supported provider:
- Surfshark, NordVPN, ExpressVPN, etc.
- WireGuard private key and addresses
- Or OpenVPN credentials

### 2. Cloudflare Tunnel Routes
After deployment, add these routes in your Cloudflare dashboard:

| Service | Internal URL | Suggested Subdomain |
|---------|-------------|-------------------|
| qBittorrent | `http://gluetun:8080` | `qbittorrent` |
| SABnzbd | `http://sabnzbd:8080` | `sabnzbd` |
| Prowlarr | `http://prowlarr:9696` | `prowlarr` |
| Sonarr | `http://sonarr:8989` | `sonarr` |
| Radarr | `http://radarr:7878` | `radarr` |
| Bazarr | `http://bazarr:6767` | `bazarr` |
| Jellyfin | `http://jellyfin:8096` | `jellyfin` |
| Plex | `http://plex:32400` | `plex` |
| Jellyseerr | `http://jellyseerr:5055` | `requests` |

## Post-Deployment Configuration

### 1. Initial Setup Order
1. **Prowlarr**: Configure indexers/trackers
2. **Sonarr/Radarr**: Link to Prowlarr and download clients
3. **Jellyfin/Plex**: Scan media libraries
4. **Jellyseerr**: Connect to media servers and managers

### 2. Directory Structure
The stack creates these volumes:
- `media_data`: Shared media storage (movies, TV shows)
- `media_downloads`: Download staging area
- Individual config volumes for each service

### 3. VPN Security
- qBittorrent traffic is routed through Gluetun VPN
- If VPN disconnects, torrenting stops automatically
- Other services (Usenet, streaming) use direct connection

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