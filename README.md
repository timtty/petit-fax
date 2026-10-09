# petite_fax

Minimal fax-receive system: [Yate](https://yate.ro) + spandsp in Docker.
Registers to a SIP/UDP trunk, answers every inbound call as a fax
receiver, and stores the result as TIFF in `spool/`.

T.38 is handled by Yate's `faxchan` (spandsp `t38_terminal`): if the
inbound INVITE — or a mid-call re-INVITE from the provider — offers
`image/t38` media, the fax is terminated over T.38/UDPTL; otherwise it
falls back to an in-band G.711 audio fax.

## Usage

1. Put your trunk credentials in `conf/accfile.conf`
   (`username`, `password`, `registrar`).
2. `docker compose up -d --build` (first build compiles Yate, takes a few minutes).
3. Watch: `docker compose logs -f` — you should see the registration succeed.
4. Send a fax to your DID. The TIFF lands in `spool/rx-<billid>-<caller>.tiff`.

View a received fax: `open spool/rx-*.tiff` (macOS Preview reads TIFF-F).

## Layout

- `conf/` — mounted at `/etc/yate` (read-only)
  - `accfile.conf` — trunk registration
  - `ysipchan.conf` — SIP listener, UDP 0.0.0.0:5060
  - `yrtpchan.conf` — RTP/UDPTL port range 20000–20100
  - `regexroute.conf` — routes every inbound call to `fax/receive/<file>`
- `spool/` — mounted at `/var/spool/fax`, received TIFFs

## Local T.38 test (no real trunk needed)

`test/` contains a trunk simulator: a second Yate container that accepts
petite_fax's REGISTER (digest auth via `regfile`) and, on command, calls
the registered endpoint with an `image/t38`-only offer and transmits
`test/fax.tiff` through spandsp's T.38 terminal.

```sh
docker compose -f docker-compose.yml -f docker-compose.test.yml up -d
./test/send-fax.sh        # originates the fax via the trunk's rmanager port
# ~20s later:
open spool/rx-*.tiff
```

Success looks like `Fax startup succeeded in digital mode` in both
containers' logs (digital = T.38; `analog mode` would mean G.711
fallback). Tear down with the same `-f` pair and `down`.

## NAT note

Media works behind Docker's NAT because most trunks do symmetric RTP
latching, and `yrtpchan` learns the remote address from the first
received packet (`autoaddr=yes`). If your provider strictly sends media
to the SDP address instead, run the container with host networking on a
box with a public IP.

## Roadmap

- **Phase 2 — direct UDP receive (no REGISTER):** the listener already
  accepts any INVITE on 5060/udp; add source-IP filtering for the
  provider and a route for the direct DID in `regexroute.conf`.
- **Phase 3 — SIP over TCP:** add a `[listener tcp5060]` section with
  `type=tcp` in `ysipchan.conf`.

## License

petite_fax's own files (Dockerfile, configs, scripts, docs) are
[MIT](LICENSE). The Docker image it builds contains third-party software
under its own licenses — notably [Yate](https://github.com/yatevoip/yate)
(GPL-2.0) and spandsp (LGPL-2.1) — so if you redistribute a built image,
those licenses' source-availability terms apply to it.
