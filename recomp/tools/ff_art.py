#!/usr/bin/env python3
"""ff_art.py <game folder> <work folder>

The launch window's art, from the player's own copy of Freedom Force (install.sh), written to a work folder that
tools/ff_art.m then composes into <data>/art (and a copy in the app). Nothing from the game is stored in this project.
  menu/char_1..6.tga   the main menu's heroes, six 256x256 tiles (3 x 2, with transparency): Data/art.ff
  menu/back_1..6.tga   the main menu's pink nebula behind them
  blue/back_1..6.tga   the blue nebula of the Load Game screen: the window's background
  menu/ff_logo_01..02  the game's logo, two tiles side by side
  keyart.jpg           GOG Galaxy's banner for the game (the team charging, 2560x670), when the GOG installer left
                       its web cache in app/webcache.zip
  steam_logo.png       the logo from the game's Steam store page (app 8880), sharper than the game's own; skipped
                       without a connection or with --offline
Whatever is missing is left out: the window falls back to the next art, then to a drawn title. Standard library only.
"""
import json, os, sys, urllib.request, zipfile

SCENES = 'Art\\library\\interface_scenes\\'
TILES = [('menu', 'mg_ff_team_main', ['char_%d' % k for k in range(1, 7)] + ['back_%d' % k for k in range(1, 7)]
          + ['ff_logo_01', 'ff_logo_02']),
         ('blue', 'mg_space_blue', ['back_%d' % k for k in range(1, 7)])]
STEAM_LOGO = 'https://cdn.cloudflare.steamstatic.com/steam/apps/8880/logo.png'


def find(folder, name):
    """a file in the game folder, its case as GOG or Steam spelled it"""
    path = folder
    for part in name.split('/'):
        try:
            hit = next((e for e in os.listdir(path) if e.lower() == part.lower()), None)
        except OSError:
            return None
        if hit is None: return None
        path = os.path.join(path, hit)
    return path


def tiles(game, out):
    art = find(game, 'Data/art.ff')
    if not art: return []
    got = []
    with zipfile.ZipFile(art) as z:
        names = {n.lower(): n for n in z.namelist()}
        for sub, scene, files in TILES:
            os.makedirs(os.path.join(out, sub), exist_ok=True)
            for f in files:
                n = names.get((SCENES + scene + '\\textures\\' + f + '.tga').lower())
                if not n: continue
                with open(os.path.join(out, sub, f + '.tga'), 'wb') as o: o.write(z.read(n))
                got.append(sub + '/' + f)
    return got


def keyart(game, out):
    cache = find(game, 'app/webcache.zip')
    if not cache: return False
    try:
        with zipfile.ZipFile(cache) as z:
            name = json.loads(z.read('resources.json')).get('images\\background')
            data = z.read(name) if name else b''
    except (KeyError, ValueError, zipfile.BadZipFile, OSError):
        return False
    if not data.startswith(b'\xff\xd8\xff') or len(data) < 50000: return False
    with open(os.path.join(out, 'keyart.jpg'), 'wb') as o: o.write(data)
    return True


def steam_logo(out):
    try:
        with urllib.request.urlopen(STEAM_LOGO, timeout=20) as r: data = r.read()
    except Exception:
        return False
    if not data.startswith(b'\x89PNG') or len(data) < 20000: return False
    with open(os.path.join(out, 'steam_logo.png'), 'wb') as o: o.write(data)
    return True


def main():
    args = [a for a in sys.argv[1:] if a != '--offline']
    if len(args) != 2: sys.exit(__doc__)
    game, out = args; os.makedirs(out, exist_ok=True)
    got = tiles(game, out)
    print('art: %d tiles from art.ff' % len(got))
    print('art: GOG key art %s' % ('found' if keyart(game, out) else 'not in this copy'))
    if '--offline' not in sys.argv: print('art: Steam logo %s' % ('downloaded' if steam_logo(out) else 'not reached'))


if __name__ == '__main__':
    main()
