// Fake Plex (port 9001), Seerr (port 9002) and Plex Watch Together (port 9003: plex.tv account,
// friends, rooms and a Syncplay relay with a pretend friend) for trying the app without real servers.
// Run: node tools/mock-servers.mjs, then launch the app with
//   CONSOLE_PLEX_URL=http://localhost:9001 CONSOLE_PLEX_TOKEN=x CONSOLE_SEERR_URL=http://localhost:9002 CONSOLE_SEERR_KEY=x
//   CONSOLE_TOGETHER_URL=http://localhost:9003 CONSOLE_PLEXTV_URL=http://localhost:9003
import http from 'node:http';
import zlib from 'node:zlib';
import fs from 'node:fs';
import crypto from 'node:crypto';

// Tiny PNG encoder for gradient poster art (Flutter can't decode SVG).
function png(w, h, h1, h2) {
  const hsl = (H, S, L) => { const a = S * Math.min(L, 1 - L); const f = (n) => { const k = (n + H / 30) % 12; return Math.round(255 * (L - a * Math.max(-1, Math.min(k - 3, 9 - k, 1)))); }; return [f(0), f(8), f(4)]; };
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const t = (x / w + y / h) / 2;
      const c1 = hsl(h1, 0.45, 0.32), c2 = hsl(h2, 0.4, 0.12);
      for (let i = 0; i < 3; i++) raw[y * (w * 3 + 1) + 1 + x * 3 + i] = Math.round(c1[i] * (1 - t) + c2[i] * t);
    }
  }
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(td)); return Buffer.concat([len, td, crc]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

const hue = (s) => [...s].reduce((a, c) => (a * 31 + c.charCodeAt(0)) % 360, 7);


// Cast & crew. Some without photos so the initials fallback shows.
const people = [
  ['Rebecca Ferguson', 'Juliette'], ['Tim Robbins', 'Bernard'], ['Common', 'Sims'], ['Harriet Walter', 'Martha'], ['Rashida Jones', 'Allison'],
  ['David Oyelowo', 'Holston'], ['Chinaza Uche', 'Paul'], ['Avi Nash', 'Lukas'], ['Iain Glen', 'Pete'], ['Shane McRae', 'Knox'],
].map(([tag, role], i) => ({ id: 5000 + i, tag, role, thumb: i % 4 === 3 ? undefined : `/people/${encodeURIComponent(tag)}` }));
const crew = { Director: [{ id: 6000, tag: 'Morten Tyldum', thumb: '/people/Morten%20Tyldum' }], Writer: [{ id: 6001, tag: 'Graham Yost' }, { id: 6002, tag: 'Hugh Howey' }, { id: 6003, tag: 'Fred Golan' }], Producer: [{ id: 6004, tag: 'Remi Aubuchon' }] };
const castFor = (i) => people.slice(i % 3, (i % 3) + 8);
const ratingsFor = (i) => [
  { image: 'imdb://image.rating', value: 7 + (i % 3) / 2, type: 'audience' },
  { image: i % 4 === 2 ? 'rottentomatoes://image.rating.rotten' : 'rottentomatoes://image.rating.ripe', value: i % 4 === 2 ? 4.2 : 8.4 + (i % 2), type: 'critic' },
  { image: 'rottentomatoes://image.rating.upright', value: 8.1, type: 'audience' },
];
// Matches a test file made with several tracks (see README "Develop"): 3 audio, 4 embedded
// subtitles, plus one sidecar subtitle served from /library/streams/99.
const streams = (i) => [
  { id: 10, index: 0, streamType: 1, codec: i % 2 ? 'hevc' : 'h264', displayTitle: i % 2 ? '4K (HEVC Main 10 HDR)' : '1080p (H.264)' },
  { id: 11, index: 1, streamType: 2, codec: 'eac3', channels: 6, bitrate: 640, languageCode: 'eng', language: 'English', title: 'English 5.1', displayTitle: 'English (EAC3 5.1)', selected: true, default: true },
  { id: 12, index: 2, streamType: 2, codec: 'aac', channels: 2, bitrate: 160, languageCode: 'eng', language: 'English', title: 'Commentary', displayTitle: 'English (AAC Stereo)', extendedDisplayTitle: 'Commentary (English AAC Stereo)' },
  { id: 13, index: 3, streamType: 2, codec: 'ac3', channels: 6, bitrate: 448, languageCode: 'spa', language: 'Español', displayTitle: 'Español (AC3 5.1)' },
  { id: 14, index: 4, streamType: 3, codec: 'srt', languageCode: 'eng', language: 'English', displayTitle: 'English (SRT)' },
  { id: 15, index: 5, streamType: 3, codec: 'srt', languageCode: 'eng', language: 'English', title: 'SDH', hearingImpaired: true, displayTitle: 'English SDH (SRT)' },
  { id: 16, index: 6, streamType: 3, codec: 'srt', languageCode: 'spa', language: 'Español', displayTitle: 'Español (SRT)' },
  { id: 17, index: 7, streamType: 3, codec: 'srt', languageCode: 'fre', language: 'Français', displayTitle: 'Français (SRT)' },
  { id: 99, streamType: 3, codec: 'srt', key: '/library/streams/99', languageCode: 'eng', language: 'English', forced: true, displayTitle: 'English Forced (SRT External)' },
];
// Intro / credits markers and chapters sized for a 75 second test clip.
const markersFor = (type) => type === 'episode'
  ? [{ type: 'intro', startTimeOffset: 4000, endTimeOffset: 18000 }, { type: 'credits', startTimeOffset: 60000, endTimeOffset: 75000, final: true }]
  : [{ type: 'credits', startTimeOffset: 62000, endTimeOffset: 75000, final: true }];
const chaptersFor = (it) => [['Opening', 0, 20000], ['The Harbor', 20000, 40000], ['Storm Front', 40000, 60000], ['End Credits', 60000, 75000]]
  .map(([tag, a, b], k) => ({ id: k + 1, index: k + 1, tag, startTimeOffset: a, endTimeOffset: b, thumb: `/still/${encodeURIComponent(it.title)}-c${k}` }));
const reviews = [
  { tag: 'Peter Debruge', source: 'Variety', image: 'rottentomatoes://image.review.fresh', text: 'A meticulously built world that rewards patience, anchored by a lead performance of real steel and wit.' },
  { tag: 'Manohla Dargis', source: 'New York Times', image: 'rottentomatoes://image.review.fresh', text: 'Ambitious, gorgeous and occasionally overwhelming, it is the rare blockbuster that trusts its audience.' },
  { tag: 'Richard Lawson', source: 'Vanity Fair', image: 'rottentomatoes://image.review.rotten', text: 'Handsome and well acted, but the story keeps circling the same ideas without ever landing them.' },
];

const movies = ['Dune: Part Two', 'Oppenheimer', 'Blade Runner 2049', 'Arrival', 'The Batman', 'Interstellar', 'Sicario', 'Prisoners', 'Heat', 'Inception', 'Past Lives', 'Everything Everywhere All at Once']
  .map((title, i) => ({ ratingKey: String(100 + i), key: `/library/metadata/${100 + i}`, type: 'movie', title, year: 2010 + (i % 14), thumb: `/thumb/${encodeURIComponent(title)}`, art: `/thumb/${encodeURIComponent(title)}`, duration: 7200000 + i * 300000, summary: `${title} follows a reluctant hero pulled into a conflict far bigger than they imagined, where every choice costs something and nobody comes out unchanged.`, contentRating: 'PG-13', audienceRating: 7 + (i % 3) / 2, Genre: [{ tag: 'Drama' }, { tag: 'Sci-Fi' }, { tag: 'Thriller' }], Media: [{ id: i, videoResolution: i % 2 ? '4k' : '1080', videoCodec: i % 2 ? 'hevc' : 'h264', container: 'mkv', bitrate: 8200 + i * 900, Part: [{ id: i, key: `/library/parts/${i}/file.mkv`, container: 'mkv', size: 4.2e9 + i * 3e8, Stream: streams(i) }] }], addedAt: 1700000000 + i, tagline: i % 2 ? 'The future belongs to those who remember.' : undefined, studio: ['Legendary', 'Universal', 'Warner Bros.', 'Paramount'][i % 4], originallyAvailableAt: `${2010 + (i % 14)}-0${1 + (i % 9)}-1${i % 9}`, Role: castFor(i), Director: crew.Director, Writer: crew.Writer.slice(0, 2), Producer: crew.Producer, Country: [{ tag: 'United States' }], Rating: ratingsFor(i), Guid: [{ id: `tmdb://${[693134, 872585, 335984, 329865, 414906, 157336, 273481, 146233, 949, 27205, 666277, 545611][i]}` }, { id: `imdb://tt${1000000 + i}` }], Review: reviews, librarySectionID: 1 }));
// Film series: parts of three franchises, so Collections has something to show.
const franchiseFilms = [
  ['Star Wars', 11, 1977, 121], ['The Empire Strikes Back', 1891, 1980, 124], ['Return of the Jedi', 1892, 1983, 131],
  ['The Lord of the Rings: The Fellowship of the Ring', 120, 2001, 178], ['The Lord of the Rings: The Two Towers', 121, 2002, 179],
  ['Harry Potter and the Philosopher\'s Stone', 671, 2001, 152], ['Pirates of the Caribbean: The Curse of the Black Pearl', 22, 2003, 143], ['Split', 381288, 2017, 117],
];
franchiseFilms.forEach(([title, tmdb, year, mins], k) => {
  const i = 12 + k, base = movies[k % movies.length];
  movies.push({ ...base, ratingKey: String(100 + i), key: `/library/metadata/${100 + i}`, title, year, originallyAvailableAt: `${year}-05-25`, thumb: `/thumb/${encodeURIComponent(title)}`, art: `/thumb/${encodeURIComponent(title)}`, duration: mins * 60000, audienceRating: 8 + (k % 3) / 3, summary: `${title} continues the saga.`, Guid: [{ id: `tmdb://${tmdb}` }], Media: base.Media, addedAt: 1690000000 + k });
});
// Watched lately (feeds "Because You Watched"); the Fellowship is finished, the Two Towers half seen.
const watchedAt = { 103: 1760300000, 115: 1760200000, 108: 1760100000 };
for (const m of movies) if (watchedAt[m.ratingKey]) { m.lastViewedAt = watchedAt[m.ratingKey]; m.viewCount = 1; }
movies.find((m) => m.ratingKey === '116').viewOffset = 4000000;
movies.find((m) => m.ratingKey === '116').lastViewedAt = 1760250000;
const plexCollections = [
  { ratingKey: '300', title: 'Star Wars Collection', tmdb: [11, 1891, 1892] },
  { ratingKey: '301', title: 'The Lord of the Rings Collection', tmdb: [120, 121] },
  { ratingKey: '302', title: 'Dune Collection', tmdb: [693134] },
  // One film only: Collections leaves it out.
  { ratingKey: '303', title: 'Nolan Picks', tmdb: [157336] },
].map((c) => ({ ...c, key: `/library/collections/${c.ratingKey}/children`, type: 'collection', subtype: 'movie', summary: '', thumb: `/thumb/${encodeURIComponent(c.title)}`, art: `/thumb/${encodeURIComponent(c.title)}`, childCount: c.tmdb.length }));
const inCollection = (c) => movies.filter((m) => c.tmdb.some((t) => m.Guid.some((g) => g.id === `tmdb://${t}`)));
const shows = ['Severance', 'The Bear', 'Andor', 'Shogun', 'Slow Horses', 'Silo']
  .map((title, i) => ({ ratingKey: String(200 + i), key: `/library/metadata/${200 + i}/children`, type: 'show', title, year: 2019 + i, thumb: `/thumb/${encodeURIComponent(title)}`, art: `/thumb/${encodeURIComponent(title)}`, childCount: 2, leafCount: 16, viewedLeafCount: 3, summary: `In ${title}, a tight-knit group is tested when a long-buried secret surfaces and the rules everyone lived by start to crack.`, contentRating: 'TV-MA', Genre: [{ tag: 'Drama' }, { tag: 'Mystery' }], studio: ['Apple TV+', 'FX', 'Disney+', 'FX', 'Apple TV+', 'Apple TV+'][i], originallyAvailableAt: `${2019 + i}-05-0${1 + i}`, Role: castFor(i), Director: crew.Director, Writer: crew.Writer, Rating: ratingsFor(i + 1), Guid: [{ id: `tmdb://${[95396, 136315, 83867, 126308, 95480, 125988][i]}` }], tagline: i === 5 ? 'Truth is buried deep.' : undefined, librarySectionID: 2 }));
const seasons = (show) => [1, 2].map((n) => ({ ratingKey: `${show.ratingKey}${n}`, key: '', type: 'season', title: `Season ${n}`, index: n, parentTitle: show.title, parentRatingKey: show.ratingKey, thumb: show.thumb, leafCount: 8, viewedLeafCount: n === 1 ? 3 : 0 }));
const episodes = (show, s) => Array.from({ length: 8 }, (_, e) => ({ ratingKey: `${show.ratingKey}${s}${e + 1}`, key: `/library/metadata/${show.ratingKey}${s}${e + 1}`, type: 'episode', title: ['Freedom Day', 'Holston\'s Pick', 'Machines', 'Truth', 'The Janitor\'s Boy', 'Hanna', 'The Flamekeepers', 'Outside'][e], index: e + 1, parentIndex: s, grandparentTitle: show.title, grandparentRatingKey: show.ratingKey, parentRatingKey: `${show.ratingKey}${s}`, grandparentThumb: show.thumb, thumb: `/still/${encodeURIComponent(show.title)}-${s}-${e}`, art: show.art, duration: 2900000 + e * 120000, summary: 'Someone finally asks the question everyone has been avoiding, and the answer changes how they see the people closest to them.', originallyAvailableAt: `${2022 + s}-0${1 + (e % 8)}-0${1 + e}`, contentRating: 'TV-MA', Rating: e % 2 ? undefined : ratingsFor(e), Media: [{ id: 900 + e, videoResolution: '1080', container: 'mkv', bitrate: 6100, Part: [{ id: 900 + e, key: `/library/parts/9${e}/file.mkv`, container: 'mkv', size: 1.9e9, Stream: streams(0) }] }], Director: e % 2 ? crew.Director : [{ id: 6005, tag: 'Adam Bernstein' }], Writer: crew.Writer.slice(e % 3, (e % 3) + 1), viewCount: s === 1 && e < 3 ? 1 : 0, viewOffset: s === 1 && e === 3 ? 41000 : undefined }));
const all = [...movies, ...shows];
const findItem = (k) => {
  const direct = all.find((x) => x.ratingKey === k);
  if (direct) return direct;
  for (const sh of shows) for (const se of seasons(sh)) { if (se.ratingKey === k) return se; for (const ep of episodes(sh, se.index)) if (ep.ratingKey === k) return ep; }
};

const json = (res, body, status = 200) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
const mc = (o) => ({ MediaContainer: o });
// Online subtitle search (Plex's OpenSubtitles lookup): results per language, and the ones
// "downloaded" onto a title, which join its streams a second after the PUT.
const fetchedSubs = new Map();
const withFetched = (it) => {
  const extra = fetchedSubs.get(it.ratingKey);
  if (!extra || !it.Media) return it;
  return { ...it, Media: it.Media.map((m, k) => k ? m : { ...m, Part: m.Part.map((pt, j) => j ? pt : { ...pt, Stream: [...pt.Stream, ...extra] }) }) };
};
const onlineSubs = (it, lang) => {
  const name = { en: 'English', fr: 'Français', es: 'Español', de: 'Deutsch' }[lang] || lang.toUpperCase();
  const slug = it.title.replace(/[^A-Za-z0-9]+/g, '.');
  return [
    { key: `/sub/${lang}/1`, title: `${slug}.${it.year ?? 2024}.1080p.BluRay.x264`, score: 96, perfectMatch: true },
    { key: `/sub/${lang}/2`, title: `${slug}.${it.year ?? 2024}.2160p.WEB-DL.DDP5.1`, score: 81 },
    { key: `/sub/${lang}/3`, title: `${slug}.${it.year ?? 2024}.720p.HDTV`, score: 64, hearingImpaired: true },
  ].map((r) => ({ id: 0, streamType: 3, codec: 'srt', language: name, languageCode: lang, providerTitle: 'OpenSubtitles', ...r }));
};

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  const p = u.pathname;
  if (p === '/') return json(res, mc({ friendlyName: 'Basement NAS', version: '1.41.3.9314-a0bfb8370', machineIdentifier: 'mock-machine' }));
  if (p === '/identity') return json(res, mc({ machineIdentifier: 'mock-machine', version: '1.41.3' }));
  if (p === '/library/sections') return json(res, mc({ Directory: [{ key: '1', title: 'Movies', type: 'movie' }, { key: '2', title: 'TV Shows', type: 'show' }] }));
  const sec = p.match(/^\/library\/sections\/(\d)\/all$/);
  if (sec) { let list = sec[1] === '1' ? movies : shows; if (u.searchParams.get('sort') === 'lastViewedAt:desc') list = [...list].sort((a, b) => (b.lastViewedAt ?? 0) - (a.lastViewedAt ?? 0)); const actor = Number(u.searchParams.get('actor')); if (actor) list = list.filter((x) => x.Role.some((r) => r.id === actor)); return json(res, mc({ size: list.length, totalSize: list.length, Metadata: list })); }
  const cols = p.match(/^\/library\/sections\/(\d)\/collections$/);
  if (cols) return json(res, mc({ Metadata: cols[1] === '1' ? plexCollections.map(({ tmdb, ...c }) => c) : [] }));
  const colKids = p.match(/^\/library\/collections\/(\d+)\/children$/);
  if (colKids) { const c = plexCollections.find((x) => x.ratingKey === colKids[1]); return json(res, mc({ Metadata: c ? inCollection(c) : [] })); }
  if (p === '/library/recentlyAdded') return json(res, mc({ Metadata: [...movies.slice(0, 8), ...shows.slice(0, 4)] }));
  if (p === '/library/onDeck') return json(res, mc({ Metadata: [{ ...movies[2], viewOffset: 3000000 }, episodes(shows[0], 1)[3], { ...movies[5], viewOffset: 900000 }] }));
  const extra = p.match(/^\/library\/metadata\/(\d+)\/extras$/);
  if (extra) {
    const it = findItem(extra[1]);
    if (!it || !['movie', 'show'].includes(it.type)) return json(res, mc({ Metadata: [] }));
    const kinds = [['Official Trailer', 'trailer', 140000], ['Making the World', 'behindTheScenes', 620000], ['The Score', 'featurette', 380000], ['Alternate Opening', 'deletedScene', 210000]];
    return json(res, mc({ Metadata: kinds.map(([title, subtype, duration], k) => ({ ratingKey: `${it.ratingKey}9${k}`, key: `/library/metadata/${it.ratingKey}9${k}`, type: 'clip', subtype, title, duration, thumb: `/still/${encodeURIComponent(it.title)}-x${k}`, Media: [{ id: 7000 + k, Part: [{ id: 7000 + k, key: `/library/parts/7${k}/file.mkv` }] }] })) }));
  }
  const rel = p.match(/^\/library\/metadata\/(\d+)\/related$/);
  if (rel) {
    const it = findItem(rel[1]);
    const pool = it?.type === 'show' ? shows : movies;
    return json(res, mc({ Hub: [{ title: 'More Like This', type: it?.type, Metadata: pool.filter((x) => x.ratingKey !== rel[1]) }] }));
  }
  const subs = p.match(/^\/library\/metadata\/(\d+)\/subtitles$/);
  if (subs) {
    const it = findItem(subs[1]);
    if (!it) return json(res, mc({}), 404);
    const lang = u.searchParams.get('language') || 'en';
    if (req.method === 'PUT') {
      const key = u.searchParams.get('key') || '';
      console.log('plex subtitle download', it.title, key);
      setTimeout(() => {
        const list = fetchedSubs.get(it.ratingKey) || [];
        const n = 500 + list.length;
        const l = key.split('/')[2] || 'en';
        list.push({ id: n, streamType: 3, codec: 'srt', key: `/library/streams/${n}`, languageCode: l, language: l, displayTitle: `${l.toUpperCase()} (SRT External, OpenSubtitles)` });
        fetchedSubs.set(it.ratingKey, list);
      }, 1000);
      return json(res, {});
    }
    return json(res, mc({ size: 3, Stream: onlineSubs(it, lang) }));
  }
  const meta = p.match(/^\/library\/metadata\/(\d+)(\/children)?$/);
  if (meta) {
    const it = findItem(meta[1]);
    if (!it) return json(res, mc({}), 404);
    if (!meta[2]) {
      const extra = u.searchParams.get('includeMarkers') ? { Marker: markersFor(it.type), Chapter: chaptersFor(it) } : {};
      return json(res, mc({ Metadata: [{ ...withFetched(it), ...extra }] }));
    }
    if (it.type === 'show') return json(res, mc({ Metadata: seasons(it) }));
    if (it.type === 'season') return json(res, mc({ Metadata: episodes(findItem(it.parentRatingKey), it.index) }));
    return json(res, mc({ Metadata: [] }));
  }
  const leaves = p.match(/^\/library\/metadata\/(\d+)\/allLeaves$/);
  if (leaves) { const show = findItem(leaves[1]); return json(res, mc({ Metadata: show ? [1, 2].flatMap((n) => episodes(show, n)) : [] })); }
  if (req.method === 'PUT' && p.startsWith('/library/parts/')) { console.log('plex select', p, u.searchParams.toString()); return json(res, {}); }
  if (p === '/library/streams/99' || /^\/library\/streams\/5\d\d$/.test(p)) {
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
    return res.end(Array.from({ length: 18 }, (_, k) => `${k + 1}\n00:00:${String(3 + k * 3).padStart(2, '0')},500 --> 00:00:${String(5 + k * 3).padStart(2, '0')},000\n[SIGN: HARBOR ${k + 1}]\n`).join('\n'));
  }
  if (p === '/hubs/search') {
    const q = (u.searchParams.get('query') || '').toLowerCase();
    return json(res, mc({ Hub: [{ type: 'movie', Metadata: movies.filter((m) => m.title.toLowerCase().includes(q)) }, { type: 'show', Metadata: shows.filter((m) => m.title.toLowerCase().includes(q)) }] }));
  }
  if (p === '/photo/:/transcode') {
    const url = decodeURIComponent((u.searchParams.get('url') || '').replace('/thumb/', ''));
    const w = Math.min(640, Number(u.searchParams.get('width')) || 240), h = Math.min(600, Number(u.searchParams.get('height')) || 360);
    res.writeHead(200, { 'content-type': 'image/png' });
    return res.end(png(w, h, hue(url), (hue(url) + 60) % 360));
  }
  if (p.startsWith('/library/parts/')) {
    // Set MOCK_VIDEO to a local video file to test direct play (Range requests supported).
    const file = process.env.MOCK_VIDEO;
    if (!file || !fs.existsSync(file)) return json(res, { error: 'set MOCK_VIDEO' }, 404);
    const size = fs.statSync(file).size;
    const m = /bytes=(\d+)-(\d*)/.exec(req.headers.range || '');
    if (m) {
      const start = Number(m[1]), end = m[2] ? Number(m[2]) : size - 1;
      res.writeHead(206, { 'content-type': 'video/x-matroska', 'accept-ranges': 'bytes', 'content-range': `bytes ${start}-${end}/${size}`, 'content-length': end - start + 1 });
      return fs.createReadStream(file, { start, end }).pipe(res);
    }
    res.writeHead(200, { 'content-type': 'video/x-matroska', 'accept-ranges': 'bytes', 'content-length': size });
    return fs.createReadStream(file).pipe(res);
  }
  if (p === '/:/timeline' || p === '/:/scrobble' || p === '/:/unscrobble') { console.log('plex', p, u.searchParams.get('state') ?? '', u.searchParams.get('time') ?? ''); return json(res, {}); }
  if (p.startsWith('/video/')) return json(res, {});
  json(res, { error: 'mock: not found' }, 404);
}).listen(9001, () => console.log('Mock Plex on http://localhost:9001'));

// ---- Seerr ----
const catalog = [
  { id: 438631, mediaType: 'movie', title: 'Dune', releaseDate: '2021-09-15', runtime: 155, tagline: 'Beyond fear, destiny awaits.', certification: 'PG-13' },
  { id: 693134, mediaType: 'movie', title: 'Dune: Part Two', releaseDate: '2024-02-27', runtime: 167, certification: 'PG-13' },
  { id: 841, mediaType: 'movie', title: 'Dune', releaseDate: '1984-12-14', runtime: 137, certification: 'PG-13' },
  { id: 90228, mediaType: 'tv', name: 'Dune: Prophecy', firstAirDate: '2024-11-17', certification: 'TV-MA', seasonsCount: 2 },
  { id: 1022789, mediaType: 'movie', title: 'Inside Out 2', releaseDate: '2024-06-11', runtime: 97, certification: 'PG' },
  { id: 762441, mediaType: 'movie', title: 'A Quiet Place: Day One', releaseDate: '2024-06-26', runtime: 99, certification: 'PG-13' },
  { id: 76479, mediaType: 'tv', name: 'The Boys', firstAirDate: '2019-07-25', certification: 'TV-MA', seasonsCount: 4 },
  { id: 157336, mediaType: 'movie', title: 'Interstellar', releaseDate: '2014-11-05', runtime: 169, certification: 'PG-13' },
  { id: 1184918, mediaType: 'movie', title: 'The Wild Robot', releaseDate: '2024-09-12', runtime: 102, certification: 'PG' },
  { id: 945961, mediaType: 'movie', title: 'Alien: Romulus', releaseDate: '2024-08-13', runtime: 119, certification: 'R' },
  { id: 94997, mediaType: 'tv', name: 'House of the Dragon', firstAirDate: '2022-08-21', certification: 'TV-MA', seasonsCount: 2 },
  { id: 1100782, mediaType: 'movie', title: 'Smile 2', releaseDate: '2024-10-16', runtime: 127, certification: 'R' },
];
const seerrPeople = [
  { id: 1373737, name: 'Rebecca Ferguson', knownForDepartment: 'Acting', birthday: '1983-10-19', placeOfBirth: 'Stockholm, Sweden', biography: 'Rebecca Ferguson is a Swedish actress. She rose to international fame playing Elizabeth Woodville in The White Queen, then Ilsa Faust in the Mission: Impossible films, Lady Jessica in Dune and Juliette Nichols in Silo.' },
  { id: 1190668, name: 'Timothée Chalamet', knownForDepartment: 'Acting', birthday: '1995-12-27', placeOfBirth: 'New York City, New York, USA', biography: 'Timothée Hal Chalamet is an American and French actor.' },
  { id: 137427, name: 'Denis Villeneuve', knownForDepartment: 'Directing', birthday: '1967-10-03', placeOfBirth: 'Bécancour, Québec, Canada', biography: 'Denis Villeneuve is a French Canadian film director and writer.' },
];
// TMDB collections (film series). Films not in the catalog yet are added to it below.
const seerrCollections = {
  10: { name: 'Star Wars Collection', films: [[11, 'Star Wars', '1977-05-25', 121], [1891, 'The Empire Strikes Back', '1980-05-20', 124], [1892, 'Return of the Jedi', '1983-05-25', 131], [1893, 'Star Wars: Episode I - The Phantom Menace', '1999-05-19', 136], [1894, 'Star Wars: Episode II - Attack of the Clones', '2002-05-15', 142], [1895, 'Star Wars: Episode III - Revenge of the Sith', '2005-05-17', 140], [140607, 'Star Wars: The Force Awakens', '2015-12-15', 136], [181808, 'Star Wars: The Last Jedi', '2017-12-13', 152], [181812, 'Star Wars: The Rise of Skywalker', '2019-12-18', 142]], overview: 'An epic space-opera theatrical film series originally created by George Lucas, following the Skywalker family across three generations as the galaxy swings between Republic, Empire and First Order.' },
  119: { name: 'The Lord of the Rings Collection', films: [[120, 'The Lord of the Rings: The Fellowship of the Ring', '2001-12-18', 178], [121, 'The Lord of the Rings: The Two Towers', '2002-12-18', 179], [122, 'The Lord of the Rings: The Return of the King', '2003-12-01', 201], [839033, 'The Lord of the Rings: The War of the Rohirrim', '2024-12-05', 134]], overview: 'The Lord of the Rings trilogy follows the hobbit Frodo Baggins and the Fellowship as they set out to destroy the One Ring and end the Dark Lord Sauron, across a Middle-earth at war.' },
  1241: { name: 'Harry Potter Collection', films: [[671, "Harry Potter and the Philosopher's Stone", '2001-11-16', 152], [672, 'Harry Potter and the Chamber of Secrets', '2002-11-13', 161], [673, 'Harry Potter and the Prisoner of Azkaban', '2004-05-31', 141], [674, 'Harry Potter and the Goblet of Fire', '2005-11-16', 157], [675, 'Harry Potter and the Order of the Phoenix', '2007-06-28', 138], [767, 'Harry Potter and the Half-Blood Prince', '2009-07-07', 153], [12444, 'Harry Potter and the Deathly Hallows: Part 1', '2010-10-17', 146], [12445, 'Harry Potter and the Deathly Hallows: Part 2', '2011-07-07', 130]], overview: 'The Harry Potter films follow a young wizard and his friends Ron and Hermione through seven years at Hogwarts School of Witchcraft and Wizardry, and the war against Lord Voldemort.' },
  295: { name: 'Pirates of the Caribbean Collection', films: [[22, 'Pirates of the Caribbean: The Curse of the Black Pearl', '2003-07-09', 143], [58, "Pirates of the Caribbean: Dead Man's Chest", '2006-07-06', 151], [285, "Pirates of the Caribbean: At World's End", '2007-05-19', 169], [1865, 'Pirates of the Caribbean: On Stranger Tides', '2011-05-14', 137], [166426, 'Pirates of the Caribbean: Dead Men Tell No Tales', '2017-05-23', 129]], overview: 'Captain Jack Sparrow sails the Caribbean in search of treasure, freedom and rum, crossing paths with cursed crews, the East India Trading Company and Davy Jones himself.' },
  558216: { name: 'Unbreakable Collection', films: [[9741, 'Unbreakable', '2000-11-22', 106], [381288, 'Split', '2017-01-19', 117], [450465, 'Glass', '2019-01-16', 129]], overview: "M. Night Shyamalan's Eastrail 177 trilogy: a security guard who has never been hurt, a man with twenty-four personalities, and the fragile mastermind who believes comic books are history." },
  // One film out and one announced: counts as a series ("1 of 2").
  948485: { name: 'The Batman Collection', films: [[414906, 'The Batman', '2022-03-01', 176], [1218925, 'The Batman Part II', '2027-10-01', 0]], overview: 'Matt Reeves\' Batman: a young Bruce Wayne, two years into his nights as the Bat, follows a killer\'s trail into the corruption of Gotham City.' },
  // A series of one: left out.
  990001: { name: 'Past Lives Collection', films: [[666277, 'Past Lives', '2023-06-02', 106]], overview: 'Childhood friends meet again.' },
  726871: { name: 'Dune Collection', films: [[438631, 'Dune', '2021-09-15', 155], [693134, 'Dune: Part Two', '2024-02-27', 167], [1170608, 'Dune: Part Three', '2026-12-16', 0]], overview: "Denis Villeneuve's adaptation of Frank Herbert's novels: Paul Atreides, heir to a noble house, is drawn into the war for the desert planet Arrakis and its spice." },
};
const media = new Map(); // tmdbId -> { status, startedAt, request, seasons }
media.set(693134, { status: 5, ratingKey: '100' });
media.set(157336, { status: 5, ratingKey: '105' });
media.set(94997, { status: 4, seasons: { 1: 5, 2: 1 } });
// All-time greats for "Top 10 Not in Your Library". Inception, Heat and Severance are in the
// mock Plex library but Seerr doesn't know, so only the Plex Guid check keeps them out.
const trendingTitles = [...catalog];
catalog.push(
  ...[
    [238, 'movie', 'The Godfather', '1972-03-14', 8.7, 21000, 'R'], [278, 'movie', 'The Shawshank Redemption', '1994-09-23', 8.7, 28000, 'R'],
    [240, 'movie', 'The Godfather Part II', '1974-12-20', 8.6, 12700, 'R'], [424, 'movie', "Schindler's List", '1993-12-15', 8.6, 16000, 'R'],
    [129, 'movie', 'Spirited Away', '2001-07-20', 8.5, 17000, 'PG'], [496243, 'movie', 'Parasite', '2019-05-30', 8.5, 19000, 'R'],
    [389, 'movie', '12 Angry Men', '1957-04-10', 8.5, 9000, 'NR'], [680, 'movie', 'Pulp Fiction', '1994-09-10', 8.5, 28000, 'R'],
    [27205, 'movie', 'Inception', '2010-07-15', 8.4, 37000, 'PG-13'], [949, 'movie', 'Heat', '1995-12-15', 7.9, 7000, 'R'],
    [372058, 'movie', 'Your Name.', '2016-08-26', 8.5, 11000, 'PG'], [346, 'movie', 'Seven Samurai', '1954-04-26', 8.5, 3700, 'NR'],
    [1396, 'tv', 'Breaking Bad', '2008-01-20', 8.9, 14000, 'TV-MA'], [94605, 'tv', 'Arcane', '2021-11-06', 8.7, 5000, 'TV-14'],
    [87108, 'tv', 'Chernobyl', '2019-05-06', 8.7, 6000, 'TV-MA'], [4613, 'tv', 'Band of Brothers', '2001-09-09', 8.5, 3500, 'TV-MA'],
    [1438, 'tv', 'The Wire', '2002-06-02', 8.6, 2600, 'TV-MA'], [95396, 'tv', 'Severance', '2022-02-17', 8.4, 2000, 'TV-MA'],
    [68595, 'tv', 'Planet Earth II', '2016-11-06', 8.7, 1500, 'TV-G'],
  ].map(([id, mediaType, title, date, voteAverage, voteCount, certification]) =>
    mediaType === 'tv'
      ? { id, mediaType, name: title, firstAirDate: date, voteAverage, voteCount, certification, seasonsCount: 3 }
      : { id, mediaType, title, releaseDate: date, voteAverage, voteCount, certification, runtime: 130 }),
);
media.set(278, { status: 5 });
for (const [cid, col] of Object.entries(seerrCollections)) for (const [id, title, releaseDate, runtime] of col.films) {
  const known = catalog.find((c) => c.id === id);
  if (known) known.inCollection = Number(cid);
  else catalog.push({ id, mediaType: 'movie', title, releaseDate, runtime, certification: 'PG-13', voteAverage: 6.4 + (id % 23) / 10, voteCount: 900, inCollection: Number(cid) });
} // Seerr says it's available (but it isn't in the mock Plex library)
let nextReq = 1;
function mkRequest(tmdbId, mediaType, status, ageMs, startedAt, seasons) {
  const prev = media.get(tmdbId) ?? {};
  const r = { id: nextReq++, status, createdAt: new Date(Date.now() - ageMs).toISOString(), type: mediaType, requestedBy: { displayName: 'Sam' }, seasons: (seasons ?? []).map((n) => ({ seasonNumber: n })) };
  const seasonMap = { ...(prev.seasons ?? {}) };
  for (const n of seasons ?? []) seasonMap[n] = status === 1 ? 2 : 3;
  media.set(tmdbId, { ...prev, status: prev.status === 4 ? 4 : (status === 1 ? 2 : 3), startedAt, request: r, mediaType, seasons: seasonMap });
  return r;
}
// Seed: one downloading, one waiting for approval, one approved but searching
mkRequest(762441, 'movie', 2, 20 * 60000, Date.now() - 6 * 60000);
mkRequest(76479, 'tv', 1, 2 * 3600000, undefined, [1, 2]);
mkRequest(1022789, 'movie', 2, 3 * 60000, null);

const DL_MS = 3 * 60000; // a mock download takes 3 minutes
function mediaInfo(item) {
  const m = media.get(item.id);
  if (!m) return undefined;
  const info = { id: item.id, tmdbId: item.id, mediaType: item.mediaType, status: m.status, ratingKey: m.ratingKey, requests: m.request ? [m.request] : [], downloadStatus: [], seasons: Object.entries(m.seasons ?? {}).map(([n, st]) => ({ seasonNumber: Number(n), status: st })) };
  if (m.startedAt === null && m.request && Date.now() - new Date(m.request.createdAt).getTime() > 30000) m.startedAt = Date.now();
  if (m.startedAt) {
    const done = (Date.now() - m.startedAt) / DL_MS;
    if (done >= 1) { m.status = 5; info.status = 5; m.ratingKey ??= '101'; info.ratingKey = m.ratingKey; m.request.status = 5; for (const n in m.seasons ?? {}) m.seasons[n] = 5; }
    else {
      const size = 8.4e9;
      info.downloadStatus = [{ size, sizeLeft: Math.round(size * (1 - done)), estimatedCompletionTime: new Date(m.startedAt + DL_MS).toISOString(), status: 'downloading', timeLeft: '', title: item.title ?? item.name }];
    }
  }
  return info;
}
const slug = (c) => encodeURIComponent(c.title ?? c.name);
const withInfo = (item) => ({ ...item, posterPath: `/p/${slug(item)}.png`, backdropPath: `/b/${slug(item)}.png`, voteAverage: item.voteAverage ?? 6.8 + (item.id % 20) / 10, voteCount: item.voteCount ?? 900, popularity: item.id % 97, mediaInfo: mediaInfo(item) });
const castOf = (c) => [
  { id: 1373737, name: 'Rebecca Ferguson', character: 'Lady Jessica', profilePath: '/f/rebecca.png' },
  { id: 1190668, name: 'Timothée Chalamet', character: 'Paul Atreides', profilePath: '/f/timothee.png' },
  { id: 3, name: 'Zendaya', character: 'Chani', profilePath: '/f/zendaya.png' },
  { id: 4, name: 'Oscar Isaac', character: 'Duke Leto', profilePath: '/f/oscar.png' },
  { id: 5, name: 'Josh Brolin', character: 'Gurney Halleck' },
  { id: 6, name: 'Javier Bardem', character: 'Stilgar', profilePath: '/f/javier.png' },
  { id: 7, name: 'Stellan Skarsgård', character: 'Baron Harkonnen', profilePath: '/f/stellan.png' },
  { id: 8, name: 'Dave Bautista', character: 'Rabban' },
].slice(c.id % 3);
function detailsOf(c) {
  const tv = c.mediaType === 'tv';
  return {
    ...withInfo(c),
    overview: `${c.title ?? c.name} is a sweeping story of power, loyalty and survival, following a family that must decide what it is willing to give up to protect the people who depend on it.`,
    genres: [{ name: tv ? 'Drama' : 'Science Fiction' }, { name: 'Adventure' }],
    credits: { cast: castOf(c), crew: [{ id: 137427, name: 'Denis Villeneuve', job: 'Director', department: 'Directing', profilePath: '/f/denis.png' }, { id: 11, name: 'Jon Spaihts', job: 'Screenplay', department: 'Writing' }, { id: 12, name: 'Eric Roth', job: 'Screenplay', department: 'Writing' }] },
    relatedVideos: [{ name: 'Official Trailer', type: 'Trailer', site: 'YouTube', key: 'n9xhJrPXop4', url: 'https://www.youtube.com/watch?v=n9xhJrPXop4' }, { name: 'Official Teaser', type: 'Teaser', site: 'YouTube', key: 'Way9Dexny3w', url: 'https://www.youtube.com/watch?v=Way9Dexny3w' }],
    externalIds: { imdbId: `tt${c.id}` },
    ...(c.inCollection ? { collection: { id: c.inCollection, name: seerrCollections[c.inCollection].name } } : {}),
    ...(tv
      ? { createdBy: [{ id: 21, name: 'Diane Ademu-John' }], networks: [{ name: 'HBO' }], episodeRunTime: [58], status: 'Returning Series', contentRatings: { results: [{ iso_3166_1: 'US', rating: c.certification }] }, seasons: [{ seasonNumber: 0, name: 'Specials', episodeCount: 3 }, ...Array.from({ length: c.seasonsCount ?? 2 }, (_, k) => ({ seasonNumber: k + 1, name: `Season ${k + 1}`, episodeCount: 8 + k, airDate: `${Number((c.firstAirDate ?? '2020').slice(0, 4)) + k}-06-01` }))] }
      : { status: 'Released', productionCompanies: [{ name: 'Legendary Pictures' }, { name: 'Warner Bros. Pictures' }], releases: { results: [{ iso_3166_1: 'US', release_dates: [{ certification: c.certification }] }] } }),
  };
}

http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  // TMDB-style images (point the app's CONSOLE_TMDB_IMAGES at http://localhost:9002/tmdb)
  if (u.pathname.startsWith('/tmdb/')) {
    const wide = u.pathname.includes('/b/') || u.pathname.includes('hqdefault');
    const face = u.pathname.includes('/f/');
    res.writeHead(200, { 'content-type': 'image/png' });
    return res.end(face ? png(185, 185, hue(u.pathname), (hue(u.pathname) + 40) % 360) : wide ? png(640, 360, hue(u.pathname), (hue(u.pathname) + 60) % 360) : png(300, 450, hue(u.pathname), (hue(u.pathname) + 60) % 360));
  }
  // Netflix's weekly Top 10 file (point CONSOLE_NETFLIX_TOP10 at http://localhost:9002/netflix/top10.tsv)
  if (u.pathname === '/netflix/top10.tsv') {
    const films = ['The Wild Robot', 'Inception', 'Smile 2', 'Alien: Romulus', 'Parasite', 'Dune', 'Pulp Fiction', 'Your Name.', 'Heat', 'Inside Out 2'];
    const tv = ['Arcane', 'The Boys', 'Severance', 'Breaking Bad', 'House of the Dragon', 'Chernobyl', 'The Wire', 'Band of Brothers', 'Dune: Prophecy', 'Planet Earth II'];
    const rows = ['week\tcategory\tweekly_rank\tshow_title\tseason_title\tweekly_hours_viewed\truntime\tweekly_views\tcumulative_weeks_in_top_10'];
    films.forEach((t, i) => rows.push(`2026-10-04\tFilms (English)\t${i + 1}\t${t}\tN/A\t1000\t2\t${9000 - i * 500}\t1`));
    tv.forEach((t, i) => rows.push(`2026-10-04\tTV (English)\t${i + 1}\t${t}\t${t}: Season 1\t1000\t8\t${8000 - i * 400}\t1`));
    rows.push('2026-09-27\tFilms (English)\t1\tLast Week Film\tN/A\t1\t1\t1\t1');
    res.writeHead(200, { 'content-type': 'text/tab-separated-values' });
    return res.end(rows.join('\n'));
  }
  // Trakt trending (point CONSOLE_TRAKT_URL at http://localhost:9002/trakt)
  const tr = u.pathname.match(/^\/trakt\/(movies|shows)\/trending$/);
  if (tr) {
    if (!req.headers['trakt-api-key']) return json(res, { error: 'no client id' }, 403);
    const type = tr[1] === 'movies' ? 'movie' : 'tv';
    const g = (u.searchParams.get('genres') ?? '').length;
    const items = catalog.filter((c) => c.mediaType === type && (c.id + g) % 2 === 0).slice(0, Number(u.searchParams.get('limit') ?? 10));
    return json(res, items.map((c, i) => ({ watchers: 500 - i * 37 + (c.id % 50), [type === 'tv' ? 'show' : 'movie']: { title: c.title ?? c.name, year: Number((c.releaseDate ?? c.firstAirDate).slice(0, 4)), ids: { trakt: i, tmdb: c.id } } })));
  }
  const p = u.pathname.replace('/api/v1', '');
  if (!req.headers['x-api-key'] && p !== '/status') return json(res, { message: 'Unauthorized' }, 403);
  if (p === '/auth/me') return json(res, { id: 1, displayName: 'Sam' });
  if (p === '/status') return json(res, { version: '2.7.3' });
  if (p === '/search') {
    const q = (u.searchParams.get('query') || '').toLowerCase();
    const hits = catalog.filter((c) => (c.title ?? c.name).toLowerCase().includes(q)).map(withInfo);
    const folks = seerrPeople.filter((x) => x.name.toLowerCase().includes(q)).map((x) => ({ ...x, mediaType: 'person' }));
    return json(res, { page: 1, totalResults: hits.length + folks.length, results: [...hits, ...folks] });
  }
  if (p === '/discover/trending') return json(res, { page: 1, results: [...trendingTitles].reverse().map(withInfo) });
  const disc = p.match(/^\/discover\/(movies|tv)$/);
  if (disc) {
    const type = disc[1] === 'movies' ? 'movie' : 'tv';
    const minVotes = Number(u.searchParams.get('voteCountGte') ?? 0), page = Number(u.searchParams.get('page') ?? 1);
    const genre = Number(u.searchParams.get('genre') ?? 0);
    // Each mock title belongs to about two genres in three.
    const provider = Number(u.searchParams.get('watchProviders') ?? 0);
    const all = catalog.filter((c) => c.mediaType === type && (!genre || (c.id + genre) % 3 !== 0) && (!provider || (c.id + provider) % 2 === 0)).map(withInfo).filter((c) => c.voteCount >= minVotes);
    if (u.searchParams.get('sortBy') === 'vote_average.desc') all.sort((a, b) => b.voteAverage - a.voteAverage);
    if (u.searchParams.get('sortBy') === 'popularity.desc') all.sort((a, b) => b.popularity - a.popularity);
    return json(res, { page, totalPages: Math.ceil(all.length / 20), results: all.slice((page - 1) * 20, page * 20) });
  }
  const sub = p.match(/^\/(movie|tv)\/(\d+)\/(ratingscombined|ratings|recommendations|similar)$/);
  if (sub) {
    if (sub[3] === 'ratingscombined') return json(res, { rt: { criticsScore: 83, criticsRating: 'Certified Fresh', audienceScore: 90, audienceRating: 'Upright' }, imdb: { criticsScore: 8.0 } });
    if (sub[3] === 'ratings') return json(res, { criticsScore: 88, criticsRating: 'Fresh', audienceScore: 79, audienceRating: 'Upright' });
    const id = Number(sub[2]);
    return json(res, { page: 1, results: catalog.filter((c) => c.id !== id && c.mediaType === sub[1]).map(withInfo).concat(catalog.filter((c) => c.mediaType !== sub[1]).slice(0, 2).map(withInfo)) });
  }
  const det = p.match(/^\/(movie|tv)\/(\d+)$/);
  if (det) {
    const c = catalog.find((x) => x.id === Number(det[2]));
    if (!c) return json(res, { message: 'Not found' }, 404);
    return json(res, detailsOf(c));
  }
  const col = p.match(/^\/collection\/(\d+)$/);
  if (col) {
    const c = seerrCollections[col[1]];
    if (!c) return json(res, { message: 'Not found' }, 404);
    return json(res, { id: Number(col[1]), name: c.name, overview: c.overview, posterPath: `/p/${encodeURIComponent(c.name)}.png`, backdropPath: `/b/${encodeURIComponent(c.name)}.png`, parts: c.films.map(([id]) => withInfo(catalog.find((x) => x.id === id))) });
  }
  const person = p.match(/^\/person\/(\d+)(\/combined_credits)?$/);
  if (person) {
    const who = seerrPeople.find((x) => x.id === Number(person[1])) ?? { id: Number(person[1]), name: 'Unknown', knownForDepartment: 'Acting' };
    if (!person[2]) return json(res, { ...who, profilePath: `/f/${who.id}.png` });
    return json(res, { id: who.id, cast: catalog.map((c, k) => ({ ...withInfo(c), character: ['Lady Jessica', 'Ilsa', 'Juliette', 'Rose'][k % 4] })), crew: [] });
  }
  if (p === '/request' && req.method === 'GET') {
    const results = [...media.entries()].filter(([, m]) => m.request).map(([id]) => {
      const c = catalog.find((x) => x.id === id);
      return { ...media.get(id).request, media: mediaInfo(c) };
    }).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    return json(res, { pageInfo: { results: results.length }, results });
  }
  if (p === '/request' && req.method === 'POST') {
    let body = '';
    for await (const c of req) body += c;
    const { mediaId, mediaType, seasons } = JSON.parse(body);
    console.log('seerr request', mediaType, mediaId, seasons ?? '');
    const c = catalog.find((x) => x.id === mediaId);
    const r = mkRequest(mediaId, mediaType, 2, 0, null, seasons);
    return json(res, { ...r, media: mediaInfo(c) }, 201);
  }
  json(res, { message: 'mock: not found' }, 404);
}).listen(9002, () => console.log('Mock Seerr on http://localhost:9002'));

// ---- Plex Watch Together (port 9003) ----
// plex.tv's account and friends, together.plex.tv's rooms, and a small Syncplay relay. "Alex"
// is a pretend friend in every room: a while after you join they pause, carry on, then jump back.
const me = { id: 7, friendlyName: 'Sam', username: 'sam' };
const friends = [
  { id: 9, title: 'Alex', username: 'alexw' },
  { id: 10, title: 'Sam', username: 'samk' },
  { id: 11, title: 'Priya', username: 'priya.r' },
];
const alexName = JSON.stringify({ deviceIdentifier: 'alex-tv', deviceName: 'Living Room TV', userID: 9 });
const rooms = new Map();
const newRoom = (title, ratingKey, createdBy, users) => {
  const id = crypto.randomUUID();
  const r = { id, title, sourceUri: `server://mock-machine/com.plexapp.plugins.library/library/metadata/${ratingKey}`, createdBy, users, startsAt: Date.now(), endsAt: Date.now() + 3 * 3600e3, syncplayHost: '127.0.0.1', syncplayPort: 9003, state: { position: 0, paused: true, at: Date.now(), setBy: null }, clients: new Set(), botTimers: [] };
  rooms.set(id, r);
  return r;
};
// An invitation from Alex turns up a few minutes in (MOCK_INVITE_AT seconds).
setTimeout(() => newRoom('The Batman', '104', friends[0], [me, friends[0]]), Number(process.env.MOCK_INVITE_AT ?? 240) * 1000);
const roomJson = (r) => { const { state, clients, botTimers, ...rest } = r; return rest; };

const wt = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname;
  let body = {};
  if (req.method === 'POST') { let s = ''; for await (const c of req) s += c; try { body = JSON.parse(s || '{}'); } catch {} }
  if (p === '/api/v2/user') return json(res, me);
  if (p === '/api/v2/friends') return json(res, friends);
  if (p === '/rooms' && req.method === 'GET') return json(res, [...rooms.values()].filter((r) => r.users.some((u) => u.id === me.id)).map(roomJson));
  if (p === '/rooms' && req.method === 'POST') {
    const rk = body.sourceUri?.split('/').pop();
    const r = newRoom(body.title, rk, me, [me, ...friends.filter((f) => (body.users ?? []).includes(f.id))]);
    return json(res, roomJson(r), 201);
  }
  const m = p.match(/^\/rooms\/([^/]+)(\/invite)?$/);
  if (m && rooms.has(m[1])) {
    const r = rooms.get(m[1]);
    if (m[2]) { for (const id of body.users ?? []) { const f = friends.find((x) => x.id === id); if (f && !r.users.includes(f)) r.users.push(f); } return json(res, roomJson(r)); }
    if (req.method === 'DELETE') { r.users = r.users.filter((u) => u.id !== me.id); for (const t of r.botTimers) clearTimeout(t); return json(res, {}); }
    return json(res, roomJson(r));
  }
  json(res, { error: 'not found' }, 404);
});

// Just enough websocket: text frames, ping and close.
const wsSend = (sock, obj) => {
  if (sock.destroyed) return;
  const data = Buffer.from(JSON.stringify(obj));
  const head = data.length < 126 ? Buffer.from([0x81, data.length]) : data.length < 65536 ? Buffer.from([0x81, 126, data.length >> 8, data.length & 255]) : null;
  sock.write(Buffer.concat([head, data]));
};
const wsFrames = (sock, onText) => {
  let buf = Buffer.alloc(0);
  sock.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    while (buf.length >= 2) {
      const op = buf[0] & 15; let len = buf[1] & 127; let off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; } else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      const masked = buf[1] & 128; const mask = masked ? buf.subarray(off, off + 4) : null; if (masked) off += 4;
      if (buf.length < off + len) return;
      const payload = Buffer.from(buf.subarray(off, off + len)); buf = buf.subarray(off + len);
      if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      if (op === 1) onText(payload.toString());
      else if (op === 9) sock.write(Buffer.concat([Buffer.from([0x8a, payload.length]), payload]));
      else if (op === 8) { sock.end(Buffer.from([0x88, 0])); }
    }
  });
};

const nowS = () => Date.now() / 1000;
const posOf = (r) => r.state.paused ? r.state.position : r.state.position + (Date.now() - r.state.at) / 1000;
const setRoom = (r, position, paused, setBy, doSeek, from) => {
  r.state = { position, paused, at: Date.now(), setBy };
  for (const c of r.clients) if (c !== from) { c.serverIgnore++; c.pendingSeek = doSeek; sendState(r, c); }
};
const sendState = (r, c) => {
  const ignore = {};
  if (c.serverIgnore) ignore.server = c.serverIgnore;
  if (c.ackClient) { ignore.client = c.ackClient; c.ackClient = 0; }
  wsSend(c.sock, { State: { playstate: { position: posOf(r), paused: r.state.paused, doSeek: !!c.pendingSeek, setBy: r.state.setBy }, ping: { latencyCalculation: nowS(), serverRtt: 0, ...(c.clientCalc ? { clientLatencyCalculation: c.clientCalc } : {}) }, ...(Object.keys(ignore).length ? { ignoringOnTheFly: ignore } : {}) } });
  c.pendingSeek = false; c.clientCalc = null;
};
const roster = (r) => ({ List: { [r.id]: Object.fromEntries([[alexName, { isReady: true, position: posOf(r) }], ...[...r.clients].filter((c) => c.name).map((c) => [c.name, { isReady: c.ready, position: posOf(r) }])]) } });

wt.on('upgrade', (req, sock) => {
  const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  sock.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  const c = { sock, name: null, ready: false, serverIgnore: 0, ackClient: 0, room: null };
  const loop = setInterval(() => c.room && sendState(c.room, c), 1000);
  sock.on('close', () => { clearInterval(loop); if (c.room) { c.room.clients.delete(c); for (const o of c.room.clients) wsSend(o.sock, { Set: { user: { [c.name]: { event: { left: true } } } } }); } });
  sock.on('error', () => {});
  wsFrames(sock, (text) => {
    let m; try { m = JSON.parse(text); } catch { return; }
    if (m.Hello) {
      const r = rooms.get(m.Hello.room?.name);
      if (!r) return wsSend(sock, { Error: { message: 'No such room' } });
      let name = m.Hello.username; while ([...r.clients].some((o) => o.name === name)) name += '_';
      c.name = name; c.room = r; r.clients.add(c);
      wsSend(sock, { Hello: { username: name, room: { name: r.id }, version: '1.2.255', realversion: '1.6.5', motd: '' } });
      for (const o of r.clients) if (o !== c) wsSend(o.sock, { Set: { user: { [name]: { room: { name: r.id }, event: { joined: true } } } } });
      // Alex: pause after a bit, carry on, then go back a little.
      if (r.clients.size === 1) {
        r.botTimers.push(setTimeout(() => setRoom(r, posOf(r), false, alexName, false), 4000));
        r.botTimers.push(setTimeout(() => setRoom(r, posOf(r), true, alexName, false), 14000));
        r.botTimers.push(setTimeout(() => setRoom(r, posOf(r), false, alexName, false), 24000));
        r.botTimers.push(setTimeout(() => setRoom(r, Math.max(3, posOf(r) - 25), false, alexName, true), 36000));
      }
      return;
    }
    if (!c.room) return;
    const r = c.room;
    if ('List' in m) wsSend(sock, roster(r));
    if (m.Set?.ready) { c.ready = !!m.Set.ready.isReady; for (const o of r.clients) wsSend(o.sock, { Set: { ready: { username: c.name, isReady: c.ready, manuallyInitiated: true } } }); }
    if (m.State) {
      const s = m.State;
      if (s.ping?.clientLatencyCalculation) c.clientCalc = s.ping.clientLatencyCalculation;
      if (s.ignoringOnTheFly?.server === c.serverIgnore) c.serverIgnore = 0;
      if (s.ignoringOnTheFly?.client && s.playstate) {
        c.ackClient = s.ignoringOnTheFly.client;
        setRoom(r, s.playstate.position, s.playstate.paused, c.name, !!s.playstate.doSeek, c);
        console.log(`[together] ${s.playstate.paused ? 'pause' : 'play'} at ${Math.round(s.playstate.position)}s${s.playstate.doSeek ? ' (seek)' : ''}`);
      }
    }
  });
});
wt.listen(9003, () => console.log('Mock Watch Together on http://localhost:9003'));
