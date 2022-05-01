# homeserver-traefik-portainer

Features:
- access all services with free TLS from letsencrypt using your own domain
- running a side project is super simple as you can plug the docker-compose file in the Portainer (directly from another repo) and even use Portainer as the docker registry
- no shell scripts are needed for maintenance
- automatic https and cert refresh
- Only 80, 443 and 9000 are needed so no problems with allocated ports (9000 if Traefik died and you want to access Portainer)
- not even ssh will be needed. Once Portainer is running through Traefik (https), everything can be updated using the UI
- multiple ways to access logs (Portainer, Dozzle)

# How to

### Warning! If a docker-compose doesn't work for you out of the box, it's probably because I use docker mapping for synology, like `/volume1/@docker:/var/lib/docker`. If that's the case, you will have to change it yourself.

1. Buy a domain. For this to work you will need to be able to create one DNS A record with a wildcard. Cloudflare offers domains at no cost (they don't make profit off it) and are great overall so I recommend them as a domain registrar.
2. You will need an ACME provider for the ACME challenge. Here's the [list of providers](https://doc.traefik.io/traefik/https/acme/#providers) supported by Traefik. If you're using Cloudflare, head over to [API Tokens](https://dash.cloudflare.com/profile/api-tokens) and create one with `Edit zone DNS` permission. Save it. You will use it for `CF_DNS_API_TOKEN` in a moment.
3. Copy `.env.example` to `.env`. Overwrite `SERVER_DOMAIN` with your domain name.
4. Now you're ready to start. In the root directory, simply `docker-compose up -d`. It will start Portainer from the compose file. This compose already has some things that will be useful for Traefik in a moment.
5. Once Portainer is up and running, head over to `http://ip-where-portainer-is-running:9000`. Go to `Settings` -> `App Templates` and replace the url with `https://raw.githubusercontent.com/tomwojcik/homeserver-traefik-portainer/master/template.json`.
6. Go to `App Templates`. Make sure you see some applications there. Deploy Traefik first.
7. When deploying Traefik you will need to set `SERVER_DOMAIN`, `ACME_EMAIL` and now is the time to use `CF_DNS_API_TOKEN`. If you want to use another challenge provider, you will have to copy this template and adjust it to fit your needs.
8. Once you click `Deploy the stack`, head over to `Traefik` stack and see logs. Make sure there are no errors. If you have problems, it's best to expose ports of Traefik and Whoami using the "edit stack" option in Portainer. Then just fix whatever is broken.
9. Now go to Cloudflare. You need to add a subdomain. Select your domain, go to DNS panel, click `Add record`. Assuming the Portainer is running on `192.168.1.2` within the local network, create record:
   1. Type: `A`
   2. Name: `*`
   3. IPv4 address: `192.168.1.2`
   4. Proxy status: disabled
10. From now on you can access Portainer (within local network) using `portainer.example.com`.
11. Deploy other stacks. Enjoy.

# My NAS-specific things

Synology uses 80 and 443 for DSM or other stuff so the ports need to be changed.
1. `sed -i -e 's/80/81/' -e 's/443/444/' /usr/syno/share/nginx/server.mustache /usr/syno/share/nginx/DSM.mustache /usr/syno/share/nginx/WWWService.mustache`
2. Depending on the DSM version, restart nginx with:
   1. `DSM<7` = `synoservicecfg --restart nginx`
   2. `DSM>=7` = `sudo systemctl restart nginx`
   
# Other stuff

I adjusted https://github.com/SimonHaas/homeserver to my needs. Big kudos to Simon Haas for sharing his stack.

[default Portainer templates](https://github.com/portainer/templates/blob/master/templates-2.0.json)

[biggest OSS templates set](https://github.com/Qballjos/portainer_templates/blob/master/Template/template.json)

[Portainer docs on templates](https://docs.portainer.io/v/ce-2.11/advanced/app-templates/format#container-template-definition-format)

# Contributing

It's my homeserver setup so if it works for me - there's nothing to improve.
If you want to star / fork / download - go ahead. I hope it makes your life easier!
