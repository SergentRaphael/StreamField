#!/usr/bin/env python3
"""Fabrique le catalogue « TV du monde » de StreamField.

Sources :
  - iptv-org  (https://github.com/iptv-org/iptv/tree/master/streams + leur base de données)
  - Free-TV   (https://github.com/Free-TV/IPTV/tree/master/lists)
  - tool/catalog/extra_sport.m3u (liste perso)

Résultat : catalog.m3u, une chaîne par entrée, regroupées par pays (« 🇫🇷 France »),
les plus connues en haut de chaque pays. Lancé chaque jour par GitHub Actions.

Usage : python3 tool/catalog/build_catalog.py <dossier_de_sortie>
"""
import json
import math
import os
import re
import sys
import unicodedata
import urllib.request
from collections import defaultdict

from babel import Locale

HERE = os.path.dirname(os.path.abspath(__file__))
API = 'https://raw.githubusercontent.com/iptv-org/api/gh-pages/'
FREETV = 'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8'

# Ordre des pays dans la colonne de gauche (les autres suivent par ordre alphabétique).
COUNTRY_ORDER = ['FR', 'BE', 'CH', 'CA', 'LU', 'MC', 'MA', 'DZ', 'TN', 'INT',
                 'GB', 'US', 'DE', 'ES', 'IT', 'PT', 'NL']

# Liens qui ne sont pas des flux directs (pages web) ou rediffusions pirates connues.
BLOCKED_HOSTS = ['youtube.com', 'youtu.be', 'twitch.tv', 'dailymotion.com', 'facebook.com',
                 'moveonjoy.com', 'thetvapp.to', 'iosplayer.ru', 'akadatel.com', 'canlitvulusal']

CATEGORIES_FR = {
    'general': 'Généraliste', 'news': 'Info', 'sports': 'Sport', 'entertainment': 'Divertissement',
    'religious': 'Religion', 'music': 'Musique', 'movies': 'Cinéma', 'kids': 'Jeunesse',
    'series': 'Séries', 'education': 'Éducation', 'legislative': 'Parlement', 'culture': 'Culture',
    'documentary': 'Documentaires', 'lifestyle': 'Art de vivre', 'shop': 'Téléachat',
    'animation': 'Animation', 'comedy': 'Humour', 'business': 'Économie', 'travel': 'Voyage',
    'classic': 'Classiques', 'outdoor': 'Nature', 'family': 'Famille', 'cooking': 'Cuisine',
    'science': 'Sciences', 'auto': 'Auto', 'public': 'Service public', 'weather': 'Météo',
    'relax': 'Détente', 'interactive': 'Interactif',
}
BIG_CATEGORIES = {'general', 'news'}


def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'StreamField-catalog'})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read().decode('utf-8', 'replace')


def norm(name):
    """« L'Équipe (1080p) [Geo-blocked] » → « lequipe »."""
    s = re.sub(r'\([^)]*\)|\[[^\]]*\]|[ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏ]', ' ', name or '')
    s = s.replace('+', ' plus ').replace('&', ' and ')
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    s = re.sub(r'[^a-z0-9]+', '', s)
    return re.sub(r'(hd|fhd|uhd|4k)$', '', s) or s


def clean_title(name):
    s = re.sub(r'\s*[ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏ]+', '', name or '')
    s = re.sub(r'\s*\((?:\d{3,4}[pi]|SD|HD)\)', '', s)
    s = re.sub(r'\s*\[[^\]]*\]', '', s)
    return s.strip()


def blocked(url):
    u = url.lower()
    return not u.startswith(('http://', 'https://')) or any(h in u for h in BLOCKED_HOSTS)


def parse_m3u(text):
    out, info, opts = [], None, {}
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith('#EXTINF'):
            attrs = dict(re.findall(r'([\w-]+)="([^"]*)"', line))
            m = re.search(r'"[^"]*"\s*,(.*)$|^#EXTINF:[^,"]*,(.*)$', line)
            name = (m.group(1) or m.group(2)) if m else ''
            info = (attrs, name.strip())
        elif line.startswith('#EXTVLCOPT:'):
            k, _, v = line[11:].partition('=')
            opts[k.strip().lower()] = v.strip()
        elif line and not line.startswith('#') and info:
            out.append({'attrs': info[0], 'name': info[1], 'url': line,
                        'ua': opts.get('http-user-agent'), 'ref': opts.get('http-referrer')})
            info, opts = None, {}
    return out


def load_top():
    top, cc = {}, None
    for raw in open(os.path.join(HERE, 'populaires.txt'), encoding='utf-8'):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        m = re.match(r'^\[([A-Z]{2,3})\]$', line)
        if m:
            cc = m.group(1)
            top.setdefault(cc, {})
        elif cc:
            pos = len(set(top[cc].values()))
            for alias in line.split('|'):
                top[cc].setdefault(norm(alias), pos)
    return top


def main(out_dir):
    print('Téléchargement des données…')
    channels = {c['id']: c for c in json.loads(fetch(API + 'channels.json'))}
    streams = json.loads(fetch(API + 'streams.json'))
    countries = {c['code']: c for c in json.loads(fetch(API + 'countries.json'))}
    feeds = json.loads(fetch(API + 'feeds.json'))
    guides = json.loads(fetch(API + 'guides.json'))
    logos = json.loads(fetch(API + 'logos.json'))
    freetv = parse_m3u(fetch(FREETV))
    extra = parse_m3u(open(os.path.join(HERE, 'extra_sport.m3u'), encoding='utf-8').read())
    top = load_top()

    # --- signaux de notoriété ---
    guide_sites = defaultdict(set)
    for g in guides:
        if g.get('channel'):
            guide_sites[g['channel']].add(g.get('site'))
    local_only = {}
    for f in feeds:
        if f.get('is_main'):
            areas = f.get('broadcast_area') or []
            local_only[f['channel']] = bool(areas) and all(a.split('/')[0] in ('ct', 's') for a in areas)
    best_logo = {}
    for l in logos:
        ch = l.get('channel')
        if not ch or not l.get('in_use', True):
            continue
        score = (l.get('feed') is None) * 4 + (l.get('format') in ('PNG', 'SVG')) * 2 + (100 <= (l.get('width') or 0) <= 1000)
        if ch not in best_logo or score > best_logo[ch][0]:
            best_logo[ch] = (score, l['url'])

    # --- candidats (une chaîne peut avoir plusieurs liens : on garde le meilleur) ---
    cands = defaultdict(list)          # clé (pays, id ou nom) → liens
    meta = {}                          # clé → infos de la chaîne
    in_freetv = set()

    def add(key, country, name, url, logo=None, category=None, labels=(), quality=None, ua=None, ref=None,
            channel_id=None, bonus=0):
        if blocked(url):
            return
        q = int(re.sub(r'\D', '', quality or '') or 0)
        link_score = bonus + (url.startswith('https')) * 1 + min(q, 1080) / 540 \
            - ('Geo-blocked' in labels) * 1 - ('Not 24/7' in labels) * 3
        cands[key].append((link_score, url, ua, ref, labels))
        m = meta.setdefault(key, {'country': country, 'name': name, 'logo': logo, 'category': category,
                                  'id': channel_id})
        m['logo'] = m['logo'] or logo
        m['category'] = m['category'] or category

    # 1) iptv-org
    for s in streams:
        ch = channels.get(s.get('channel') or '')
        if not ch or ch.get('is_nsfw') or ch.get('closed') or 'xxx' in ch.get('categories', []):
            continue
        cc = 'GB' if ch['country'] == 'UK' else ch['country']
        cat = next((c for c in ch.get('categories', []) if c in CATEGORIES_FR), None)
        add((cc, ch['id']), cc, ch['name'], s['url'], best_logo.get(ch['id'], (0, None))[1], cat,
            tuple(s.get('labels') or ()), s.get('quality'), s.get('user_agent'), s.get('referrer'), ch['id'])

    by_name = {}
    for ch in channels.values():
        cc = 'GB' if ch['country'] == 'UK' else ch['country']
        for n in [ch['name']] + (ch.get('alt_names') or []):
            by_name.setdefault((cc, norm(n)), ch['id'])

    # 2) Free-TV (relié à iptv-org par son identifiant ou son nom quand c'est possible)
    for e in freetv:
        a = e['attrs']
        group = a.get('group-title', '')
        if group.startswith('VOD'):
            continue
        cc = (a.get('tvg-country') or '').upper()[:2] or 'INT'
        cc = 'GB' if cc == 'UK' else cc
        cid = (a.get('tvg-id') or '').split('@')[0]
        if cid not in channels:
            cid = by_name.get((cc, norm(e['name'])), cid)
        key = (cc, cid) if cid in channels else (cc, 'n:' + norm(e['name']))
        labels = ('Geo-blocked',) if 'Ⓖ' in e['name'] else ()
        cat = None
        if cid in channels:
            cat = next((c for c in channels[cid].get('categories', []) if c in CATEGORIES_FR), None)
        add(key, cc, clean_title(e['name']), e['url'], a.get('tvg-logo') or None, cat, labels,
            None, e['ua'], e['ref'], cid if cid in channels else None, bonus=1)
        in_freetv.add(key)

    # --- fusion des doublons (même nom dans le même pays) ---
    merged = {}
    for key in sorted(cands, key=lambda k: (meta[k]['id'] is None, str(k))):
        m = meta[key]
        nk = (m['country'], norm(m['name']))
        if nk in merged and merged[nk] != key:
            target = merged[nk]
            cands[target].extend(cands.pop(key))
            meta[target]['logo'] = meta[target]['logo'] or m['logo']
            if key in in_freetv:
                in_freetv.add(target)
        else:
            merged[nk] = key

    # --- score de notoriété et tri ---
    entries = defaultdict(list)
    for key, links in cands.items():
        m = meta[key]
        cc, cid = m['country'], m['id']
        ch = channels.get(cid or '', {})
        names = [m['name']] + (ch.get('alt_names') or [])
        rank = min((top.get(cc, {}).get(norm(n), 10**6) for n in names), default=10**6)
        links.sort(key=lambda l: -l[0])
        best = links[0]
        fame = (min(len(guide_sites.get(cid, ())), 25) * 2
                + (key in in_freetv) * 6
                + min(len(links), 5)
                + (m['logo'] is not None) * 2
                + (m['category'] in BIG_CATEGORIES) * 3
                + (bool(ch.get('network'))) * 3
                - local_only.get(cid, False) * 8
                - ('Not 24/7' in best[4]) * 6)
        name = m['name']
        if 'Geo-blocked' in best[4]:
            name += ' (géo-bloquée)'
        if 'Not 24/7' in best[4] and 'pas 24h' not in name:
            name += ' (pas 24h/24)'
        entries[cc].append((rank, -fame, norm(m['name']), {
            'name': name, 'url': best[1], 'logo': m['logo'], 'tvg': cid or '',
            'category': CATEGORIES_FR.get(m['category'] or '', ''), 'ua': best[2], 'ref': best[3]}))

    fr = Locale('fr').territories

    def country_label(cc):
        if cc == 'INT':
            return '🌍 International'
        info = countries.get(cc) or countries.get('UK' if cc == 'GB' else cc, {})
        return f"{info.get('flag', '')} {fr.get(cc, info.get('name', cc))}".strip()

    def sort_key(cc):
        if cc in COUNTRY_ORDER:
            return (0, COUNTRY_ORDER.index(cc), '')
        return (1, 0, unicodedata.normalize('NFKD', fr.get(cc, cc)).encode('ascii', 'ignore').decode().lower())

    lines, total, summary = ['#EXTM3U'], 0, []

    # Ta liste perso : TOUS ses liens, tels quels et dans son ordre, en tête de la colonne de gauche.
    mine = '⚽ Ma liste sport'
    for e in extra:
        attrs = f'group-title="{mine}" category="Sport"'
        if e['attrs'].get('tvg-logo'):
            attrs += f' tvg-logo="{e["attrs"]["tvg-logo"]}"'
        lines.append(f'#EXTINF:-1 {attrs},{e["name"].replace(",", " ")}')
        lines.append(e['url'])
        total += 1
    summary.append((mine, len(extra), [e['name'] for e in extra[:6]]))
    for cc in sorted(entries, key=sort_key):
        group = country_label(cc).replace('"', "'")
        items = sorted(entries[cc], key=lambda e: e[:3])
        summary.append((group, len(items), [i[3]['name'] for i in items[:6]]))
        for *_, e in items:
            attrs = f'tvg-id="{e["tvg"]}"' if e['tvg'] else ''
            if e['logo']:
                attrs += f' tvg-logo="{e["logo"]}"'
            attrs += f' group-title="{group}"'
            if e['category']:
                attrs += f' category="{e["category"]}"'
            lines.append(f'#EXTINF:-1 {attrs.strip()},{e["name"].replace(",", " ")}')
            if e['ua']:
                lines.append(f'#EXTVLCOPT:http-user-agent={e["ua"]}')
            if e['ref']:
                lines.append(f'#EXTVLCOPT:http-referrer={e["ref"]}')
            lines.append(e['url'])
            total += 1

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'catalog.m3u'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    with open(os.path.join(out_dir, 'README.md'), 'w', encoding='utf-8') as f:
        f.write('# Catalogue StreamField\n\nMis à jour automatiquement chaque jour.\n\n'
                f'**{total} chaînes** dans **{len(summary)} pays**.\n\n| Pays | Chaînes | En haut de la liste |\n|---|---|---|\n')
        for g, n, firsts in summary:
            f.write(f'| {g} | {n} | {", ".join(firsts)} |\n')
    print(f'{total} chaînes, {len(summary)} pays')
    for g, n, firsts in summary[:12]:
        print(f'  {g:28} {n:5}  {" | ".join(firsts)}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'catalog_out')
