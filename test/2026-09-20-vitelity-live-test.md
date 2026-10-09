# Live trunk test — Vitelity vFax → petite_fax

**Date:** 2026-09-20, 18:24–18:27 UTC (12:24–12:27 MDT)
**Goal:** end-to-end receive test over the real Vitelity trunk (not the
`test/` simulator), using two real-world PDFs with different page
characteristics.

## Result

Both faxes were accepted by Vitelity, delivered to the registered
petite_fax container, and written to `spool/` complete and legible.

| # | Document | Pages | jobid | Vitelity status | Received TIFF | Bytes |
|---|---|---|---|---|---|---|
| 1 | `chicken.pdf` | 3 | 868189513 | Success | `spool/rx-1789926932-1-8025550100.tiff` | 199474 |
| 2 | `writersblock.pdf` | 1 | 868189739 | Success | `spool/rx-1789926932-2-8025550100.tiff` | 25854 |

Page counts in the received TIFFs match the source PDFs (3 and 1). Both
calls ended `Phase E state 0x0: OK` followed by our `BYE`.

Received TIFF format (both): 1728 × 2156, 1 bpp, CCITT Group 3, 204 × 196
dpi, `PhotometricInterpretation=WhiteIsZero`, `description=+18025550100`.
Page 1 of each was rendered and inspected visually — body text, the
flowchart figure in `chicken.pdf`, and the 6 pt footnotes in
`writersblock.pdf` are all clean.

## Test documents

Chosen as a contrasting pair: one dense multi-page document with line-art,
one nearly blank page with fine print at the margins.

- `chicken.pdf` — Doug Zongker, *"Chicken Chicken Chicken: Chicken Chicken"*,
  3 pages. Two-column body text plus a boxes-and-arrows figure.
  <https://isotropic.org/papers/chicken.pdf>
- `writersblock.pdf` — Dennis Upper, *"The Unsuccessful Self-Treatment of a
  Case of 'Writer's Block'"*, JABA 1974, 1 page. Famously empty body;
  exercises large white areas plus small type in the header and footnotes.
  <https://monoskop.org/images/3/3a/Upper_Dennis_1974_The_Unsuccessful_Self-Treatment_of_a_Case_of_Writers_Block.pdf>

## Setup

Receiver: the normal `docker-compose.yml` container (`petite-fax`),
registered as `<sip-user>@<vitelity-registrar>` with `interval=120`.
Registration was healthy throughout (19 × `200 OK` to REGISTER in the log).

Sender: Vitelity's vFax API via a small local client script,
`vitelity_fax.py` (not part of this repo). Numbers below are placeholders.

```sh
export VITELITY_CREDENTIALS_FILE=/path/to/vitelity_api_creds   # USER= / PASS= lines
export VITELITY_FAX_FROM=8025550100                      # vFax DID we send from
python3 vitelity_fax.py \
    send --to 8025550199 --name "Petite-Fax Test 1" test/chicken.pdf
```

Route: vFax DID **8025550100** → DID **8025550199**, which is the number
that rings our SIP registration.
Delivery was confirmed with `vitelity_fax.py status --jobid <id>`.

## Findings

### 1. Vitelity's vFax originator never offers T.38

Both calls arrived as audio-only INVITEs and no mid-call re-INVITE to
`image/t38` ever came, so faxchan ran in **analog mode** (in-band G.711
fax) both times:

```
<INFO> Routing call to '8025550199' in context 'default' via
       'fax/receive//var/spool/fax/rx-1789926932-1-8025550100.tiff' in 77 usec
<fax/1:INFO> Fax startup succeeded in analog mode
<sip/1:INFO> Formats for 'audio' changed to 'alaw,mulaw'
```

The G.711 fallback path is therefore proven against a real carrier, but
the **T.38 path remains verified only by the local trunk simulator** in
`test/`. If T.38 over the live trunk matters, it likely has to be enabled
on the Vitelity side — nothing in petite_fax's config can force it when
the offer never contains `image/t38`.

Media traversed Docker's NAT without trouble, as the README's NAT note
predicts (symmetric latching + `autoaddr=yes`).

### 2. `ECM carrier not found` is benign noise on this path

Both calls logged, a few seconds after Phase B:

```
<fax/1:INFO> Phase B message 0x83: DCS
WARNING T.30 fax/1 ECM carrier not found
```

Both then transferred every page correctly and finished `Phase E state
0x0: OK`. With `faxecm=true` in `regexroute.conf`, treat this warning as
expected on G.711 calls from Vitelity, not as a failure signal.

### 3. Spool file size is not a completion signal

faxchan creates the TIFF at **8 bytes** as soon as the call is routed and
appends each page as it lands, so the file exists — and looks stable
between pages — long before the fax is done. Fax 1 sat at 8 bytes for
~40 s, then grew 67 KB → 129 KB → 199 KB as the three pages arrived.

Poll the container log for `Phase E state 0x0: OK` (or count IFDs in the
TIFF) instead of watching file size.

### 4. Timing

| Phase | Fax 1 (3 pp) | Fax 2 (1 pp) |
|---|---|---|
| API accept → inbound INVITE | ~10 s | ~15 s |
| Phase B (DCS) → first page | 41 s | 17 s |
| Per additional page | 33–39 s | — |
| Total call duration | 2 m 03 s | 27 s |

Roughly 35–40 s per dense page at 204 × 196 dpi over G.711. The nearly
blank page took half that. Vitelity's `status` for a job stays
`Processing` with `pages: 0` for the whole call and only flips to
`Success` after the far end hangs up — so it lags the receiver's own
completion by a few seconds and is not useful for live progress.

### 5. Filename collisions

`${billid}` turns out to be `<timestamp>-<sequence>`, so two calls in the
same session produced `rx-1789926932-1-…` and `rx-1789926932-2-…` rather
than two identical names. The existing naming scheme is safe for
back-to-back faxes.

## Reproducing

The PDFs are not committed (third-party papers); fetch them from the
links above into `test/`. With the container up and registered:

```sh
curl -Lo test/chicken.pdf https://isotropic.org/papers/chicken.pdf
export VITELITY_CREDENTIALS_FILE=/path/to/vitelity_api_creds
export VITELITY_FAX_FROM=8025550100
FAX="python3 vitelity_fax.py"

$FAX send --to 8025550199 --name "Petite-Fax Test" --dry-run test/chicken.pdf
$FAX send --to 8025550199 --name "Petite-Fax Test" test/chicken.pdf

docker logs -f petite-fax 2>&1 | grep -aE "fax/[0-9]|T\.30"   # wait for Phase E OK
open spool/rx-*.tiff
```

Each send is a real, billable fax. Dry-run first.
