# Yate + spandsp fax receiver (T.38 capable)
FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git ca-certificates \
        autoconf automake libtool pkg-config \
        libspandsp-dev libtiff-dev \
    && rm -rf /var/lib/apt/lists/*

# Pinned yate master (official GitHub mirror), 2026-09
ARG YATE_COMMIT=7d86cb173a7b19a051cecb63f905919f4b93df01
RUN git clone https://github.com/yatevoip/yate.git /usr/src/yate \
    && cd /usr/src/yate && git checkout "$YATE_COMMIT"

WORKDIR /usr/src/yate
# Debian puts spandsp.h in the multiarch dir, which yate's configure
# doesn't scan
RUN ln -s "/usr/include/$(gcc -print-multiarch)/spandsp.h" /usr/include/spandsp.h \
    && ./autogen.sh \
    # the webrtc-based codecs pull in miniwebrtc, which doesn't compile on
    # arm64; none of them is needed for fax
    && ./configure --prefix=/usr --sysconfdir=/etc \
        --disable-ilbc-webrtc --disable-isac-float --disable-g722-webrtc \
    # yate's Makefiles are not parallel-safe; build serially
    && make \
    && make install-noapi DESTDIR=/stage

# Fail the build early if faxchan didn't get built (spandsp not detected)
RUN test -f /stage/usr/lib/yate/faxchan.yate


FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        libspandsp2 libtiff6 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/spool/fax

COPY --from=build /stage/ /

EXPOSE 5060/udp

# -vv: debug level "info"; logs go to stderr (docker logs)
CMD ["yate", "-vv"]
