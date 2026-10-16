"""Offline-Test der Empfehlung mit echten Bewertungen aus MovieLens 32M.

Ablauf (fester Zufallsstartwert, jeder Lauf liefert dieselben Zahlen):
1. Bewertungen auf die Filme unseres Katalogs beschränken (Zuordnung über die IMDb-Nummer).
2. Personen mit mindestens 20 solchen Bewertungen in drei Gruppen teilen:
   Training (Modell lernen), Abstimmung (Gewichte wählen), Test (nur einmal messen).
3. Jede Test- bzw. Abstimmungsperson mit mindestens 40 Bewertungen "swipt" 12 echte Bewertungen
   wie im Onboarding. Jedes Verfahren schlägt aus ihren übrigen Filmen 5 vor.
4. Treffer = selbst mit mindestens 4 Sternen und über dem eigenen Schnitt bewertet.
   Flop = selbst mit höchstens 2,5 Sternen bewertet.

Aufruf: python3 empfehlungstest.py <films.json> <ml-32m-Ordner>
Daten: https://grouplens.org/datasets/movielens/32m/ (nur nicht kommerziell)
"""
import csv, json, sys, random, collections
import numpy as np

FILMS, ML = sys.argv[1], sys.argv[2]
films = {f["id"]: f for f in json.load(open(FILMS)) if f.get("type") != "series"}
imdb2id = {f["imdbID"]: fid for fid, f in films.items() if f.get("imdbID")}
ml2id = {}
for r in csv.DictReader(open(f"{ML}/links.csv")):
    key = "tt" + r["imdbId"].zfill(7)
    if key in imdb2id: ml2id[r["movieId"]] = imdb2id[key]

rows = collections.defaultdict(dict)
with open(f"{ML}/ratings.csv") as fin:
    next(fin)
    for line in fin:
        u, m, r, _ = line.split(",", 3)
        fid = ml2id.get(m)
        if fid: rows[int(u)][fid] = float(r)

users = sorted(u for u, d in rows.items() if len(d) >= 20)
random.Random(1).shuffle(users)
n = len(users)
test_pool, tune_pool, train = users[: n // 5], users[n // 5 : n // 5 + n // 10], users[n // 5 + n // 10 :]
print(f"Katalog: {len(films)} Filme, davon {len(set(ml2id.values()))} in MovieLens")
print(f"Personen mit ≥20 Bewertungen: {n} · Training {len(train)} · Abstimmung {len(tune_pool)} · Test {len(test_pool)}")

# Modell wie in der App: Filmbonus + 24 Geschmacksfaktoren (Matrix-Faktorisierung, ALS), nur aus Trainingspersonen
items = sorted({f for u in train for f in rows[u]}); idx = {f: i for i, f in enumerate(items)}
K, LAM, LB = 24, 8.0, 25.0
U = []
for u in train:
    ii = np.array([idx[f] for f in rows[u]]); rr = np.array(list(rows[u].values())); U.append((ii, rr - rr.mean()))
s = np.zeros(len(items)); c = np.zeros(len(items))
for ii, rr in U: np.add.at(s, ii, rr); np.add.at(c, ii, 1)
b = s / (c + LB)
U = [(ii, rr - b[ii]) for ii, rr in U]
iu = collections.defaultdict(list)
for ui, (ii, rr) in enumerate(U):
    for i, r in zip(ii, rr): iu[i].append((ui, r))
I = [(np.array([a for a, _ in iu[i]], dtype=int), np.array([x for _, x in iu[i]])) for i in range(len(items))]
rs = np.random.default_rng(0); P = rs.normal(0, .1, (len(train), K)); Q = rs.normal(0, .1, (len(items), K))
for _ in range(10):
    for ui, (ii, rr) in enumerate(U):
        Qi = Q[ii]; P[ui] = np.linalg.solve(Qi.T @ Qi + LAM * np.eye(K), Qi.T @ rr)
    for i, (uu, rr) in enumerate(I):
        if len(uu): Pu = P[uu]; Q[i] = np.linalg.solve(Pu.T @ Pu + LAM * np.eye(K), Pu.T @ rr)
print("Modell gelernt:", len(items), "Filme")

# Signale und Merkmale wie in der App (RecommendationEngine.swift)
def content(f):
    out = {"g:" + g: 1.0 for g in f["genres"]}; out.update({"m:" + m: 1.2 for m in f["moods"]})
    if f.get("director"): out["d:" + f["director"]] = 0.8
    for x in f["cast"][:2]: out["c:" + x] = 0.4
    return out
CONTENT = {fid: content(films[fid]) for fid in items}
SIG = {"loved": 2.0, "liked": 1.0, "disliked": -1.0}
TARGET = {"loved": 1.0, "liked": 0.3, "disliked": -1.0}
def label(r): return "loved" if r >= 4.5 else "liked" if r >= 3.5 else "disliked"
imdb = np.array([(films[f].get("imdbRating") or 7) - 7 for f in items])

def content_ridge(onb, lam=3.0):
    X = [CONTENT[f] for f, _ in onb]; y = np.array([SIG[s] for _, s in onb]); y = y - 0.5 * y.mean()
    Km = np.array([[sum(v * o.get(k, 0) for k, v in a.items()) for o in X] for a in X]) + lam * np.eye(len(X))
    al = np.linalg.solve(Km, y); w = collections.defaultdict(float)
    for a, x in zip(al, X):
        for k, v in x.items(): w[k] += a * v
    return lambda f: sum(w.get(k, 0) * v for k, v in CONTENT[f].items())

def foldin(onb, lam):
    ii = np.array([idx[f] for f, _ in onb]); y = np.array([TARGET[s] for _, s in onb])
    y = y - 0.5 * y.mean() - b[ii]; Qi = Q[ii]
    return np.linalg.solve(Qi.T @ Qi + lam * np.eye(K), Qi.T @ y)

def evaluate(pool, configs):
    res = collections.defaultdict(list); people = 0
    for u in pool:
        d = {f: r for f, r in rows[u].items() if f in idx}
        if len(d) < 40: continue
        fs = sorted(d); random.Random(u).shuffle(fs)
        onb = [(f, label(d[f])) for f in fs[:12]]; cand = fs[12:]
        mean = np.mean(list(d.values()))
        rel = {f for f in cand if d[f] >= 4.0 and d[f] >= mean + 0.25}; bad = {f for f in cand if d[f] <= 2.5}
        if not rel: continue
        people += 1
        ci = np.array([idx[f] for f in cand]); cr = content_ridge(onb); cc = np.array([cr(f) for f in cand])
        rnd = random.Random(u * 7 + 3)
        sc = {"Zufall": np.array([rnd.random() for _ in cand]),
              "IMDb-Bestenliste": imdb[ci],
              "Nur Genre und Stimmung": cc + 0.35 * imdb[ci]}
        cache = {}
        for name, (lam, a) in configs.items():
            if lam not in cache: cache[lam] = foldin(onb, lam)
            sc[name] = b[ci] + Q[ci] @ cache[lam] + 0.08 * imdb[ci] + a * cc
        for name, v in sc.items():
            top = [cand[j] for j in np.argsort(-v, kind="stable")[:5]]
            res[name].append((sum(f in rel for f in top) / 5, top[0] in rel, sum(f in bad for f in top) / 5))
    return people, {k: tuple(np.mean([x[i] for x in v]) * 100 for i in range(3)) for k, v in res.items()}

def table(title, people, r):
    print(f"\n--- {title}: {people} Personen ---")
    print(f"{'Verfahren':30} {'Top-5-Treffer':>13} {'Platz 1 passt':>14} {'Flops in Top 5':>15}")
    for k, (a, p1, fl) in r.items(): print(f"{k:30} {a:12.1f}% {p1:13.1f}% {fl:14.1f}%")

# 1) Gewichte nur an der Abstimmungsgruppe wählen
grid = {f"λ{lam:g} + Inhalt×{a:g}": (lam, a) for lam in (50.0, 100.0, 200.0) for a in (0.0, 0.03, 0.06)}
p, r = evaluate(tune_pool, grid); table("Abstimmung", p, r)
best = max(grid, key=lambda k: r[k][0]); print("gewählt:", best, "· in der App: λ100 + Inhalt×0.06")
# 2) Einmal an der Testgruppe messen: App-Einstellung und an der Abstimmung gewählte Einstellung
p, r = evaluate(test_pool, {"Unser Modell (App)": (100.0, 0.06), f"Unser Modell ({best})": grid[best]}); table("Test", p, r)
