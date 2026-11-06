#!/usr/bin/env python3
"""Builds Liquiflux's TV collection pack (app/assets/collections/tv-pack.json).

Programming blocks (Toonami, Nick at Nite...) come from Wikipedia list pages: each table
row's or bullet's first link is a show, Wikidata gives its TVDB/TMDB/IMDb ids, and TVmaze
confirms it's a series and adds a rating, popularity and poster. Networks come from
TVmaze's show index (the network a show premiered on). No API keys are needed.

Runs in GitHub Actions (.github/workflows/collection-pack.yml); standard library only.
    python3 tools/collection-pack/build_pack.py [--only toonami,net-hbo] [--cache DIR]
Writes the pack plus a report (tools/collection-pack/report.md) listing what didn't match.
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, 'app', 'assets', 'collections', 'tv-pack.json')
REPORT = os.path.join(HERE, 'report.md')
UA = 'LiquifluxCollectionPack/1.0 (https://github.com/Foehammer1987/Liquiflux)'
WIKI = 'https://en.wikipedia.org/w/api.php'
WIKIDATA = 'https://www.wikidata.org/w/api.php'
SPARQL = 'https://query.wikidata.org/sparql'
TVMAZE = 'https://api.tvmaze.com'
POSTER_PREFIX = 'https://static.tvmaze.com/uploads/images/medium_portrait/'

# Wikidata "instance of" values that mean a film, not a series.
FILM_TYPES = {'Q11424', 'Q202866', 'Q24862', 'Q506240', 'Q20650540', 'Q29168811', 'Q220898'}

cache_dir = None
_last_call = {}


def _throttle(host, gap):
    now = time.monotonic()
    wait = _last_call.get(host, 0) + gap - now
    if wait > 0:
        time.sleep(wait)
    _last_call[host] = time.monotonic()


def fetch(url, data=None, gap=0.2, accept='application/json'):
    """GET (or POST form data) with a disk cache, polite pacing and retries. None on 404."""
    key = hashlib.sha1((url + '\n' + (data or '')).encode()).hexdigest()
    path = os.path.join(cache_dir, key[:2], key) if cache_dir else None
    if path and os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            text = f.read()
        return None if text == '\0404' else text
    host = urllib.parse.urlparse(url).netloc
    for attempt in range(6):
        _throttle(host, gap)
        req = urllib.request.Request(url, data=data.encode() if data else None, headers={'User-Agent': UA, 'Accept': accept})
        if data:
            req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                text = r.read().decode('utf-8')
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                text = '\0404'
                break
            if e.code in (429, 500, 502, 503, 504) and attempt < 5:
                time.sleep(2 ** attempt + 1)
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 5:
                time.sleep(2 ** attempt + 1)
                continue
            raise
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
    return None if text == '\0404' else text


def fetch_json(url, data=None, gap=0.2):
    text = fetch(url, data, gap)
    return None if text is None else json.loads(text)


def wiki(params):
    return fetch_json(WIKI + '?' + urllib.parse.urlencode({**params, 'format': 'json', 'formatversion': 2}), gap=0.1)


# ---------------------------------------------------------------- Wikipedia parsing

LINK = re.compile(r'\[\[([^\[\]|#]+)(?:#[^\[\]|]*)?(?:\|[^\[\]]*)?\]\]')
HEADING = re.compile(r'^(={2,6})\s*(.*?)\s*\1\s*$')
SKIP_NS = re.compile(r'^(file|image|category|wikipedia|wp|template|help|portal|special|wikt|wiktionary|s|d|commons|list of|lists of)\s*:', re.I)


def _clean_heading(h):
    return re.sub(r'<[^>]+>|\[\[(?:[^|\]]*\|)?([^\]]*)\]\]|\'{2,}', lambda m: m.group(1) or '', h).strip()


def _first_link(text):
    for m in LINK.finditer(text):
        target = m.group(1).strip()
        if not target or SKIP_NS.match(target):
            continue
        return target[0].upper() + target[1:]
    return None


def page_rows(wikitext, sections=None, skip=None):
    """The first linked title of every table row and top-level bullet, with its heading."""
    inc = re.compile(sections, re.I) if sections else None
    exc = re.compile(skip, re.I) if skip else None
    heads = []  # stack of (level, text)
    out = []
    in_table = 0
    row = []

    def heading_ok():
        path = ' / '.join(h for _, h in heads)
        if exc and any(exc.search(h) for _, h in heads):
            return False
        if inc and not any(inc.search(h) for _, h in heads):
            return False
        return True

    def flush_row():
        if not row:
            return
        cells = []
        for line in row:
            # "| a || b" and "! a !! b" hold several cells on one line.
            body = line[1:]
            parts = re.split(r'\|\||!!', body)
            for p in parts:
                # Drop cell attributes: 'style="..." | content'.
                if '|' in p and '[[' not in p.split('|', 1)[0] and '=' in p.split('|', 1)[0]:
                    p = p.split('|', 1)[1]
                cells.append(p)
        for c in cells[:2]:  # the title is in the first cell, sometimes after a row header
            t = _first_link(c)
            if t:
                out.append((t, ' / '.join(h for _, h in heads), ''.join(cells)))
                break
        row.clear()

    for raw in wikitext.split('\n'):
        line = raw.strip()
        m = HEADING.match(line)
        if m and not in_table:
            level = len(m.group(1))
            while heads and heads[-1][0] >= level:
                heads.pop()
            heads.append((level, _clean_heading(m.group(2))))
            continue
        if line.startswith('{|'):
            in_table += 1
            row.clear()
            continue
        if line.startswith('|}'):
            if in_table == 1 and heading_ok():
                flush_row()
            row.clear()
            in_table = max(0, in_table - 1)
            continue
        if in_table == 1:
            if line.startswith('|-'):
                if heading_ok():
                    flush_row()
                row.clear()
            elif line.startswith('|+'):
                continue
            elif line.startswith('|') or line.startswith('!'):
                if line.startswith('!') and not row and not LINK.search(line):
                    continue  # a column header row
                row.append(line)
            elif row:
                row[-1] += ' ' + line
            continue
        if in_table == 0 and re.match(r'^\*(?!\*)', line) and heading_ok():
            # Only the bullet's lead: "* ''[[Show]]'' (1999–2001) – replaced [[Other]]".
            lead = re.split(r'\s[–—-]\s|\(|:', line, maxsplit=1)[0]
            t = _first_link(lead)
            if t:
                out.append((t, ' / '.join(h for _, h in heads), line))
    return out


def years_in(text):
    ys = [int(y) for y in re.findall(r'\b(19[4-9]\d|20[0-4]\d)\b', text)]
    return (min(ys), max(ys)) if ys else None


# ---------------------------------------------------------------- Wikidata

def resolve_qids(titles):
    """Wikipedia title → Wikidata id, following redirects."""
    out = {}
    titles = list(dict.fromkeys(titles))
    for i in range(0, len(titles), 50):
        batch = titles[i:i + 50]
        j = wiki({'action': 'query', 'prop': 'pageprops', 'ppprop': 'wikibase_item', 'redirects': 1, 'titles': '|'.join(batch)})
        q = (j or {}).get('query', {})
        alias = {}
        for n in q.get('normalized', []):
            alias[n['to']] = alias.get(n['from'], n['from'])
        back = {}
        for t in batch:
            back[t] = t
        for n in q.get('normalized', []):
            back[n['to']] = n['from']
        for r in q.get('redirects', []):
            back[r['to']] = back.get(r['from'], r['from'])
        for p in q.get('pages', []):
            qid = (p.get('pageprops') or {}).get('wikibase_item')
            if qid:
                out[back.get(p['title'], p['title'])] = qid
                out[p['title']] = qid
    return out


def _claims(entity, prop):
    vals = []
    for c in entity.get('claims', {}).get(prop, []):
        v = c.get('mainsnak', {}).get('datavalue', {}).get('value')
        if isinstance(v, dict) and 'id' in v:
            v = v['id']
        elif isinstance(v, dict) and 'time' in v:
            v = v['time']
        if v is not None:
            vals.append(v)
    return vals


def entities(qids):
    out = {}
    qids = list(dict.fromkeys(qids))
    for i in range(0, len(qids), 50):
        j = fetch_json(WIKIDATA + '?' + urllib.parse.urlencode({'action': 'wbgetentities', 'ids': '|'.join(qids[i:i + 50]), 'props': 'claims|labels', 'languages': 'en', 'format': 'json'}), gap=0.1)
        for qid, e in ((j or {}).get('entities') or {}).items():
            if 'missing' in e:
                continue
            tmdb = [v for v in _claims(e, 'P4983') if str(v).isdigit()]
            tvdb = [v for v in _claims(e, 'P4835') if str(v).isdigit()]
            imdb = [v for v in _claims(e, 'P345') if str(v).startswith('tt')]
            starts = [int(v[1:5]) for v in _claims(e, 'P580') + _claims(e, 'P577') if isinstance(v, str) and re.match(r'^\+\d{4}', v)]
            out[qid] = {
                'tmdb': int(tmdb[0]) if tmdb else None,
                'tvdb': int(tvdb[0]) if tvdb else None,
                'imdb': imdb[0] if imdb else None,
                'types': set(_claims(e, 'P31')),
                'year': min(starts) if starts else None,
                'label': (e.get('labels', {}).get('en') or {}).get('value'),
            }
    return out


def tmdb_by_external(tvdbs, imdbs):
    """TMDB TV ids for TVDB / IMDb ids, through Wikidata's query service."""
    out_tvdb, out_imdb = {}, {}
    for ids, prop, out in ((sorted(tvdbs), 'P4835', out_tvdb), (sorted(imdbs), 'P345', out_imdb)):
        ids = [str(i) for i in ids]
        for i in range(0, len(ids), 300):
            values = ' '.join('"%s"' % x for x in ids[i:i + 300])
            q = 'SELECT ?x ?tmdb WHERE { VALUES ?x { %s } ?item wdt:%s ?x; wdt:P4983 ?tmdb. }' % (values, prop)
            j = fetch_json(SPARQL, urllib.parse.urlencode({'query': q, 'format': 'json'}), gap=1.0)
            for b in (j or {}).get('results', {}).get('bindings', []):
                t = b['tmdb']['value']
                if t.isdigit():
                    out.setdefault(b['x']['value'], int(t))
    return out_tvdb, out_imdb


# ---------------------------------------------------------------- TVmaze

def tvmaze_lookup(imdb=None, tvdb=None):
    for k, v in (('imdb', imdb), ('thetvdb', tvdb)):
        if v:
            j = fetch_json(f'{TVMAZE}/lookup/shows?{k}={v}', gap=0.55)
            if j:
                return j
    return None


def tvmaze_search(title, year):
    j = fetch_json(f'{TVMAZE}/search/shows?' + urllib.parse.urlencode({'q': title}), gap=0.55) or []
    want = _norm(title)
    for hit in j:
        s = hit.get('show') or {}
        y = _year(s.get('premiered'))
        if _norm(s.get('name') or '') == want and (year is None or (y is not None and abs(y - year) <= 1)):
            return s
    return None


def tvmaze_index():
    page = 0
    while True:
        j = fetch_json(f'{TVMAZE}/shows?page={page}', gap=0.55)
        if not j:
            return
        yield from j
        page += 1


def _year(d):
    return int(d[:4]) if isinstance(d, str) and re.match(r'^\d{4}', d) else None


def _norm(s):
    return re.sub(r'[^a-z0-9]', '', s.lower().replace('&', 'and'))


# ---------------------------------------------------------------- the pack

class Shows:
    """Every show once, keyed by its TVmaze id."""

    def __init__(self):
        self.rows = []
        self.by_maze = {}

    def add(self, s, tmdb=None):
        mid = s['id']
        if mid in self.by_maze:
            i = self.by_maze[mid]
            if tmdb and not self.rows[i].get('tm'):
                self.rows[i]['tm'] = tmdb
            return i
        ext = s.get('externals') or {}
        img = ((s.get('image') or {}).get('medium') or '')
        row = {'t': s.get('name') or '?'}
        y = _year(s.get('premiered'))
        if y:
            row['y'] = y
        if tmdb:
            row['tm'] = tmdb
        if ext.get('thetvdb'):
            row['tv'] = ext['thetvdb']
        if ext.get('imdb'):
            row['im'] = ext['imdb']
        r = (s.get('rating') or {}).get('average')
        if r:
            row['r'] = round(float(r), 1)
        if s.get('weight'):
            row['w'] = int(s['weight'])
        if img.startswith(POSTER_PREFIX):
            row['p'] = img[len(POSTER_PREFIX):]
        self.rows.append(row)
        self.by_maze[mid] = len(self.rows) - 1
        return self.by_maze[mid]


def build_block(b, shows, report):
    rows = []
    for page in b['pages']:
        j = wiki({'action': 'parse', 'page': page, 'prop': 'wikitext', 'redirects': 1})
        if not j or 'parse' not in j:
            report.append(f'- **{b["name"]}**: page "{page}" not found')
            continue
        text = j['parse']['wikitext']
        heads = [_clean_heading(m.group(2)) for m in (HEADING.match(l.strip()) for l in text.split('\n')) if m]
        report.append(f'- **{b["name"]}** ({page}): headings: {", ".join(heads[:40])}')
        rows += page_rows(text, b.get('sections'), b.get('skip'))
    titles = [t for t, _, _ in rows]
    qids = resolve_qids(titles)
    ents = entities(set(qids.values()))
    picked, misses, seen = [], [], set()
    for title, head, line in rows:
        e = ents.get(qids.get(title, ''), None)
        if e and e['types'] & FILM_TYPES:
            continue
        s = None
        if e and (e['imdb'] or e['tvdb']):
            s = tvmaze_lookup(e['imdb'], e['tvdb'])
        if s is None and e:
            yr = years_in(line)
            s = tvmaze_search(e['label'] or title, e['year'] or (yr[0] if yr else None))
        if s is None:
            if e is not None:
                misses.append(f'{title} ({head})')
            continue
        if s['id'] in seen:
            continue
        seen.add(s['id'])
        picked.append(shows.add(s, e['tmdb'] if e else None))
    report.append(f'  - {len(rows)} rows, {len(picked)} shows, {len(misses)} series-like rows not on TVmaze')
    for m in misses[:60]:
        report.append(f'    - not matched: {m}')
    return picked


def main():
    global cache_dir
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', help='comma-separated collection ids')
    ap.add_argument('--cache', default=os.path.join(HERE, '.cache'))
    ap.add_argument('--no-networks', action='store_true')
    args = ap.parse_args()
    cache_dir = args.cache
    with open(os.path.join(HERE, 'sources.json'), encoding='utf-8') as f:
        src = json.load(f)
    only = set(args.only.split(',')) if args.only else None

    shows = Shows()
    report = [f'# Collection pack report ({datetime.date.today().isoformat()})', '', '## Blocks', '']
    collections = []
    for b in src['blocks']:
        if only and b['id'] not in only:
            continue
        ids = build_block(b, shows, report)
        print(f'{b["id"]}: {len(ids)} shows', flush=True)
        if ids:
            collections.append({'id': b['id'], 'kind': 'block', 'name': b['name'], 'years': b.get('years'), 'about': b.get('about'),
                                'source': 'https://en.wikipedia.org/wiki/' + urllib.parse.quote(b['pages'][0].replace(' ', '_')), 'shows': ids})

    nets = [n for n in src['networks'] if not only or n['id'] in only]
    if nets and not args.no_networks:
        report += ['', '## Networks', '']
        want = {}
        for n in nets:
            for name, country in n['tvmaze']:
                want.setdefault((name.lower(), country), []).append(n['id'])
        members = {n['id']: [] for n in nets}
        for s in tvmaze_index():
            if (s.get('type') or '') in ('Talk Show', 'News', 'Sports', 'Game Show', 'Award Show'):
                continue
            ch = s.get('network') or s.get('webChannel')
            if not ch:
                continue
            country = (ch.get('country') or {}).get('code')
            for key in ((ch.get('name', '').lower(), country), (ch.get('name', '').lower(), None)):
                for nid in want.get(key, []):
                    members[nid].append(s)
        # TMDB ids for network shows, from Wikidata, by TVDB and IMDb id.
        allshows = [s for v in members.values() for s in v]
        tv, im = tmdb_by_external({(s.get('externals') or {}).get('thetvdb') for s in allshows} - {None},
                                  {(s.get('externals') or {}).get('imdb') for s in allshows} - {None})
        for n in nets:
            got = members[n['id']]
            ids = []
            for s in sorted(got, key=lambda s: -(s.get('weight') or 0)):
                ext = s.get('externals') or {}
                tm = tv.get(str(ext.get('thetvdb'))) or im.get(ext.get('imdb') or '')
                i = shows.add(s, tm)
                if i not in ids:
                    ids.append(i)
            report.append(f'- **{n["name"]}**: {len(ids)} shows')
            print(f'{n["id"]}: {len(ids)} shows', flush=True)
            if ids:
                collections.append({'id': n['id'], 'kind': 'network', 'name': n['name'], 'source': 'https://www.tvmaze.com', 'shows': ids})

    # Fill in TMDB ids the blocks' Wikidata items didn't have.
    need = [r for r in shows.rows if not r.get('tm')]
    if need:
        tv, im = tmdb_by_external({r['tv'] for r in need if r.get('tv')}, {r['im'] for r in need if r.get('im')})
        for r in need:
            t = tv.get(str(r.get('tv'))) or im.get(r.get('im') or '')
            if t:
                r['tm'] = t

    pack = {
        'format': 1,
        'built': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'credits': 'Show lists from Wikipedia (CC BY-SA 4.0) and TVmaze (CC BY-SA 4.0); ids from Wikidata (CC0).',
        'posterBase': POSTER_PREFIX,
        'shows': shows.rows,
        'collections': collections,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(pack, f, ensure_ascii=False, separators=(',', ':'))
    no_tmdb = sum(1 for r in shows.rows if not r.get('tm'))
    report[1:1] = ['', f'{len(collections)} collections, {len(shows.rows)} shows, {no_tmdb} without a TMDB id, {os.path.getsize(OUT) // 1024} KB.']
    with open(REPORT, 'w', encoding='utf-8') as f:
        f.write('\n'.join(report) + '\n')
    print(f'wrote {OUT}: {len(collections)} collections, {len(shows.rows)} shows ({no_tmdb} without TMDB id)')


if __name__ == '__main__':
    sys.exit(main())
