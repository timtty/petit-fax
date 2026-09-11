#!/bin/sh
# Originate a T.38 test fax from the trunk simulator to petite_fax.
# Requires the test stack:
#   docker compose -f docker-compose.yml -f docker-compose.test.yml up -d
{
    printf 'call fax/transmit//test/fax.tiff petite\r\n'
    sleep 2
    printf 'quit\r\n'
} | nc 127.0.0.1 5038
