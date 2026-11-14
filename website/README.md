# Better at Gambling website

Static one-page site with a three.js casino hall that the camera travels down while you scroll
(logo coin sign, roulette table, shove gag, Big Wheel and Peg Drop, Last Call, results podium).
No build step: plain ES modules, three.js r170 and Lenis are vendored in `vendor/`.

- `index.html`, `css/style.css`: page and copy (from the Steam store text, trademark-safe names).
- `js/main.js`: renderer, scroll camera, stations, chip rain, confetti, UI.
- `js/bean.js`: the bean rebuilt after `player/avatar_visuals.gd`.
- `js/props.js`: chips, roulette, cards, Big Wheel, Peg Drop, marquee signs, podium, columns.
- `assets/`: logo glb (`assets/models/logo/logo_3d.glb`), Poly Haven statue and bust (CC0), card
  faces, Barlow Condensed (OFL), screenshots and clips from the Steam kit, a 720p trailer.

`.gdignore` keeps Godot from importing this folder, and the release workflow ignores `website/**`.

## Run locally

    cd website && python3 -m http.server 8000   # then open http://localhost:8000

## Hosting (VPS, betteratgambling.com)

`deploy/docker-compose.yml` serves the folder with nginx on 127.0.0.1:8152. The host nginx site in
`deploy/host-nginx-betteratgambling.conf` proxies the domain to it; certbot adds HTTPS.
`deploy/update.sh` pulls the newest version and restarts the container (site.conf is a single-file bind mount, so nginx reload is not enough).
