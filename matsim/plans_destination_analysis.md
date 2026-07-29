# Plans file analysis: destination centroid snapping

**File analysed:** `plans_2023.xml` (425 MB) — MATSim v6 synthetic population, Auckland 2023
**Date:** 2026-06-15
**CRS:** NZTM2000 / EPSG:2193 (metres)

---

## 1. What the file is

`plans_2023.xml` is the **travel-demand input** for an agent-based MATSim
simulation of Auckland (the baseline / "do-nothing" scenario). Each `<person>`
is one synthetic traveller; each `<plan>` is that person's daily schedule of
activities joined by trips (`<leg>`).

> **Provenance note.** This file was added by collaborator *SpatialEconomics*
> (commit `fc3565f`, "Auckland 2023 Base", 2026-06) as `plans_2023.7z`. It is a
> **separate work stream** from the `data-analysis/` OD/network scripts in this
> repo (authored by *Hyesop*, 2025-10). The exact pipeline and zoning system
> used to generate the synthetic population are **not documented here** — the
> statements below distinguish what is proven from the file itself versus what
> is inferred. Confirm provenance with SpatialEconomics before citing.

| Element | Count | Meaning |
|---|---:|---|
| `<person>` | 1,650,844 | synthetic agents (modelled population) |
| mobile agents (≥1 trip) | 686,560 | people who leave home that day |
| stay-at-home agents | ~964,000 | single `home` activity only |
| `<leg>` (trips) | 1,431,382 | journeys to be simulated |
| `<activity>` | 3,082,226 | home / work / education stops |

**Activity types:** home 2,366,535 · work 339,510 · education 376,181
(commuting + education only — no shopping/leisure/other).

**Trip modes:** car 626,058 · ride 364,598 · walk 228,492 · pt 200,468 ·
bike 9,890 · other 1,876.

**ID scheme:** `AKL_<household>_<person>` — people in the same household share a
home location (e.g. `AKL_260772_1`, `AKL_260772_2`).

### Reading one agent

```xml
<person id="AKL_2_1">
  <plan selected="yes">
    <activity type="home" x="1715347.32" y="5976613.23" end_time="07:07:00"/>
    <leg mode="car"/>
    <activity type="work" x="1748230.17" y="5970616.42" end_time="15:59:00"/>
    <leg mode="car"/>
    <activity type="home" x="1715347.32" y="5976613.23"/>
  </plan>
</person>
```

Home until 07:07 → drive to work → work until 15:59 → drive home. A classic
morning/evening-peak commuter. Congestion is **not** baked into this file — it
emerges when MATSim loads all these trips onto the network and agents compete
for the same links in the peak.

---

## 2. Key finding: destinations are snapped to SA2 centroids

Activity locations are placed by **two different mechanisms**:

| Activity | Activities | Distinct locations |
|---|---:|---:|
| home | 2,366,535 | **319,192** |
| work | 339,510 | **589** |
| education | 376,181 | **487** |

- **Homes are fine** — 319k distinct points dispersed across the whole region
  (bounding box ≈ 116 km × 124 km). Trustworthy trip origins.
- **Work / education are coarse** — only ~589 / 487 distinct points. Every
  worker/student in a zone is dropped on that zone's single centroid.

### Proof it is centroid snapping (not real addresses)

Comparing the exact coordinate sets (to 15 decimal places):

| Test | Result | Interpretation |
|---|---:|---|
| points shared by **work AND education** | **460** | both draw from one common centroid lookup |
| points shared by **home** with work/edu | **0** | homes use a separate, finer mechanism |

A factory and a school cannot share a coordinate to the millimetre by chance —
**460 exact matches** between the work and education layers proves both are
snapped to a shared set of zone reference points. **This much is proven from the
file alone.**

**What is inferred, not proven:** that the zoning system is *SA2*. The count
(~589) is in the SA2 ballpark (local `sa3_akl.gpkg` has 186 SA3s; SA2s are ~3×
finer ≈ 550–600), but the synthetic population's pipeline is undocumented here
and the zoning could equally be SA1, meshblock, TAZ, or another scheme. The
`OD_by_SA2.csv` in this repo is a **separate analysis by a different author** and
is *not* confirmed to be the input that generated this file. To verify the
zoning, overlay the 589 work points on candidate boundary layers and check
whether each sits at a zone centroid (see `disaggregate_destinations.R` step 3,
which assigns points to whatever boundary layer you supply).

> The "all homes identical" impression when opening the file is a **sorting
> artifact** — the population is written grouped by household, so the first ~130
> consecutive records happen to share a home. It is not a real defect.

---

## 3. Why it matters for congestion pricing

Origins are well-resolved but **destinations over-concentrate**, which:

- **artificially concentrates congestion** on ~589 network nodes and their
  feeder links;
- **biases cordon membership** — whether an agent's route crosses a priced link
  depends on a centroid that may sit on the wrong side of the boundary;
- **zeroes out intra-zone trips** (distance collapses to 0 within a zone).

For a cordon/zone-based pricing study this distorts both *which* agents are
charged and *where* congestion appears — so destination disaggregation is the
highest-value preprocessing step before running priced scenarios.

---

## 4. Fix: `disaggregate_destinations.R`

Script: [`disaggregate_destinations.R`](disaggregate_destinations.R)
(sf + tidyverse, EPSG:2193).

**Pipeline**

1. Read SA2 2023 polygons.
2. Assign each distinct destination centroid to its containing SA2
   (`st_within`, nearest-SA2 fallback).
3. Pre-sample a per-zone jitter pool (`st_sample`) sized to that zone's number
   of activities — every agent gets a fresh in-zone point, no two coincide.
4. Stream-rewrite the 425 MB XML line-by-line (each activity is one line),
   replacing only `work`/`education` coordinates. **Homes untouched.**
5. Output `plans_2023_disaggregated.xml` + a sanity check (distinct work points
   should rise from 589 to ~the activity count).

**Prerequisite (you supply):** the repo ships only SA3 boundaries. Download
"Statistical Area 2 2023 (generalised)" from
[datafinder.stats.govt.nz](https://datafinder.stats.govt.nz), clip to Auckland,
save as `matsim-plans/sa2_akl.gpkg`. Adjust `SA2_CODE` if the code field is
named differently. The script stops with this instruction if the file is absent.

**Run**

```bash
cd matsim-plans
Rscript disaggregate_destinations.R
```

**Options**

- `LANDUSE_MASK` — set to a built-up/road polygon so jittered points avoid
  harbour and parks (Auckland has many coastal SA2s).
- For `work`, sampling could be weighted by an employment surface instead of
  uniform — a natural next refinement if a land-use raster is available.

**Verified**

- Extraction returns 715,691 destinations (339,510 work + 376,181 education ✓).
- The pool lookup key is the verbatim coordinate string (not a double —
  converting would round 17→15 digits and silently break the join); confirmed
  byte-for-byte on real lines, and the rewrite preserves `end_time`.

---

## 5. Known limitations of the baseline demand

- **Commute/education only** — no shopping, leisure or freight trips, so
  off-peak and discretionary traffic is absent. Acceptable for a peak-hour
  commuting CP study, but state it explicitly.
- **Destination disaggregation pending** — addressed by the script above.
