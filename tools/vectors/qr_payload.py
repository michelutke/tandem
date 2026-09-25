"""Reference parser + generator for protocol/vectors/qr-payload.json (E01-21).

Implements `docs/protocol/SPEC.md` §2's `pair-uri` ABNF grammar and its field-by-field
parse/reject rules:

    pair-uri = "tandem://pair?v=1&fp=" fp "&s=" s "&a=" addr-list "&p=" port "&n=" name

`parse_pair_uri` is the reference decoder a conformance runner re-implements; `dataclasses`/stdlib
`ipaddress` and `base64` do the address/encoding validation so this module carries no third-party
dependency.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import ipaddress
import urllib.parse
from dataclasses import dataclass
from typing import Any

MAX_ADDRESSES = 8
MAX_NAME_BYTES = 64
FINGERPRINT_BYTES = 32
SECRET_BYTES = 16
REQUIRED_FIELDS = ("v", "fp", "s", "a", "p", "n")

_BASE64URL_ALPHABET = frozenset(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
)


@dataclass(frozen=True)
class QrPayloadParseResult:
    accepted: bool
    version: str | None = None
    fingerprint: bytes | None = None
    secret: bytes | None = None
    addresses: tuple[str, ...] | None = None
    port: int | None = None
    name: bytes | None = None
    error: str | None = None
    field: str | None = None


def _reject(error: str, field: str | None = None) -> QrPayloadParseResult:
    return QrPayloadParseResult(False, error=error, field=field)


def _decode_base64url_no_padding(value: str, *, expected_length: int, field: str, wrong_length_error: str) -> tuple[bytes | None, QrPayloadParseResult | None]:
    if not value or any(ch not in _BASE64URL_ALPHABET for ch in value):
        return None, _reject("invalidEncoding", field)
    padded = value + "=" * (-len(value) % 4)
    try:
        decoded = base64.urlsafe_b64decode(padded)
    except (binascii.Error, ValueError):
        return None, _reject("invalidEncoding", field)
    if len(decoded) != expected_length:
        return None, _reject(wrong_length_error, field)
    return decoded, None


def _validate_addresses(raw: str) -> tuple[tuple[str, ...] | None, QrPayloadParseResult | None]:
    if raw == "":
        return None, _reject("invalidAddress", "a")

    candidates = raw.split(",")
    if len(candidates) > MAX_ADDRESSES:
        return None, _reject("tooManyAddresses", "a")

    for candidate in candidates:
        if not candidate or "%" in candidate:
            # Empty entry (e.g. a trailing comma) or an IPv6 zone ID (`%en0`): SPEC.md §2
            # permits no zone identifier on a literal-addr.
            return None, _reject("invalidAddress", "a")
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            # Not a literal IPv4/IPv6 address at all (e.g. a hostname).
            return None, _reject("invalidAddress", "a")
        if address.is_unspecified or address.is_multicast:
            return None, _reject("invalidAddress", "a")
        if isinstance(address, ipaddress.IPv4Address) and address == ipaddress.IPv4Address("255.255.255.255"):
            return None, _reject("invalidAddress", "a")

    return tuple(candidates), None


def _validate_port(raw: str) -> tuple[int | None, QrPayloadParseResult | None]:
    if not raw.isdigit() or len(raw) > 5:
        return None, _reject("invalidPort", "p")
    if len(raw) > 1 and raw[0] == "0":
        return None, _reject("invalidPort", "p")
    port = int(raw)
    if not (1 <= port <= 65535):
        return None, _reject("invalidPort", "p")
    return port, None


def _validate_name(raw: str) -> tuple[bytes | None, QrPayloadParseResult | None]:
    try:
        decoded = urllib.parse.unquote_to_bytes(raw)
    except Exception:
        return None, _reject("invalidName", "n")
    if len(decoded) > MAX_NAME_BYTES:
        return None, _reject("invalidName", "n")
    return decoded, None


def parse_pair_uri(uri: str) -> QrPayloadParseResult:
    if "://" not in uri:
        return _reject("invalidScheme")
    scheme, remainder = uri.split("://", 1)
    if scheme != "tandem":
        return _reject("invalidScheme")

    if "?" in remainder:
        host, query = remainder.split("?", 1)
    else:
        host, query = remainder, ""
    if host != "pair":
        return _reject("invalidHost")

    fields: dict[str, str] = {}
    for pair in ([] if query == "" else query.split("&")):
        key, _, value = pair.partition("=")
        if key in fields:
            return _reject("duplicatedField", key)
        fields[key] = value

    missing = [name for name in REQUIRED_FIELDS if name not in fields]
    if missing:
        return _reject("missingRequiredField", missing[0])

    if fields["v"] != "1":
        return _reject("unsupportedVersion", "v")

    fingerprint, err = _decode_base64url_no_padding(
        fields["fp"], expected_length=FINGERPRINT_BYTES, field="fp", wrong_length_error="invalidFingerprint"
    )
    if err is not None:
        return err

    secret, err = _decode_base64url_no_padding(
        fields["s"], expected_length=SECRET_BYTES, field="s", wrong_length_error="invalidSecret"
    )
    if err is not None:
        return err

    addresses, err = _validate_addresses(fields["a"])
    if err is not None:
        return err

    port, err = _validate_port(fields["p"])
    if err is not None:
        return err

    name, err = _validate_name(fields["n"])
    if err is not None:
        return err

    return QrPayloadParseResult(
        True,
        version=fields["v"],
        fingerprint=fingerprint,
        secret=secret,
        addresses=addresses,
        port=port,
        name=name,
    )


# --- manifest generation (E01-21) --------------------------------------------------------------


def _base64url_no_padding(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _fixed_fingerprint(label: str) -> bytes:
    return hashlib.sha256(f"tandem-vectors:qr-fp:{label}".encode("ascii")).digest()


def _fixed_secret(label: str) -> bytes:
    return hashlib.sha256(f"tandem-vectors:qr-secret:{label}".encode("ascii")).digest()[:SECRET_BYTES]

FP_A = _fixed_fingerprint("mac-a")
SECRET_A = _fixed_secret("mac-a")


def _build_uri(
    *,
    v: str = "1",
    fp: bytes | str = FP_A,
    s: bytes | str = SECRET_A,
    addresses: list[str] | str = ("192.168.1.10",),
    port: int | str = 54321,
    name: bytes | str = b"Michel's MacBook Pro",
) -> str:
    fp_str = _base64url_no_padding(fp) if isinstance(fp, (bytes, bytearray)) else fp
    s_str = _base64url_no_padding(s) if isinstance(s, (bytes, bytearray)) else s
    addr_str = ",".join(addresses) if not isinstance(addresses, str) else addresses
    port_str = str(port) if isinstance(port, int) else port
    name_str = urllib.parse.quote(name.decode("utf-8") if isinstance(name, (bytes, bytearray)) else name, safe="")
    return f"tandem://pair?v={v}&fp={fp_str}&s={s_str}&a={addr_str}&p={port_str}&n={name_str}"


def _valid_vector(vector_id: str, description: str, **build_kwargs: Any) -> dict[str, Any]:
    uri = _build_uri(**build_kwargs)
    result = parse_pair_uri(uri)
    assert result.accepted, f"{vector_id} was expected to parse; got error {result.error!r}"
    return {
        "id": vector_id,
        "description": description,
        "input": {"uri": uri},
        "expected": {
            "version": result.version,
            "fingerprintHex": result.fingerprint.hex(),
            "secretHex": result.secret.hex(),
            "addresses": list(result.addresses),
            "port": result.port,
            "nameHex": result.name.hex(),
        },
    }


def _malformed_vector(vector_id: str, description: str, *, uri: str) -> dict[str, Any]:
    result = parse_pair_uri(uri)
    assert not result.accepted, f"{vector_id} was expected to fail to parse; got {result}"
    entry: dict[str, Any] = {
        "id": vector_id,
        "description": description,
        "input": {"uri": uri},
        "expectedError": result.error,
    }
    if result.field is not None:
        entry["input"]["invalidField"] = result.field
    return entry


def generate_qr_payload_vectors() -> dict[str, Any]:
    ipv6_examples = ["2001:db8::1", "fe80::abcd:1234:ffff:1"]
    eight_addresses = [f"10.0.0.{i}" for i in range(1, 8)] + ["2001:db8::10"]
    nine_addresses = [f"10.0.0.{i}" for i in range(1, 9)] + ["2001:db8::10"]

    vectors = [
        _valid_vector(
            "qr-payload-single-address",
            "Well-formed payload with a single IPv4 address.",
            addresses=["192.168.1.10"],
        ),
        _valid_vector(
            "qr-payload-mixed-address-list",
            "Well-formed payload with a mixed IPv4/IPv6 address list, including a loopback "
            "address (SPEC.md §2: loopback is not one of the forbidden categories, only the "
            "Mac's own QR-rendering code chooses never to emit one).",
            addresses=["127.0.0.1", *ipv6_examples],
        ),
        _valid_vector(
            "qr-payload-max-address-list",
            "Well-formed payload with the maximum 8 literal addresses.",
            addresses=eight_addresses,
        ),
        _malformed_vector(
            "qr-payload-missing-field",
            "The `s` field is entirely absent from the query string.",
            uri="tandem://pair?v=1&fp=" + _base64url_no_padding(FP_A) + "&a=192.168.1.10&p=54321&n=Mac",
        ),
        _malformed_vector(
            "qr-payload-duplicated-field",
            "The `p` field appears twice in the query string.",
            uri=_build_uri() + "&p=1234",
        ),
        _malformed_vector(
            "qr-payload-padded-base64url-fp",
            "`fp` is base64url-encoded with trailing `=` padding, which SPEC.md §2's grammar "
            "(`fp = 1*BASE64URL`, no padding character in the alphabet) forbids.",
            uri=_build_uri(fp=_base64url_no_padding(FP_A) + "="),
        ),
        _malformed_vector(
            "qr-payload-fingerprint-wrong-length",
            "`fp` decodes to 31 bytes instead of the required 32.",
            uri=_build_uri(fp=FP_A[:-1]),
        ),
        _malformed_vector(
            "qr-payload-secret-wrong-length",
            "`s` decodes to 15 bytes instead of the required 16.",
            uri=_build_uri(s=SECRET_A[:-1]),
        ),
        _malformed_vector(
            "qr-payload-port-zero",
            "`p` is 0, one below the 1..65535 range.",
            uri=_build_uri(port=0),
        ),
        _malformed_vector(
            "qr-payload-port-too-large",
            "`p` is 65536, one above the 1..65535 range.",
            uri=_build_uri(port=65536),
        ),
        _malformed_vector(
            "qr-payload-port-leading-zero",
            "`p` is `00080`, carrying a leading zero the grammar's `1*5DIGIT` forbids.",
            uri=_build_uri(port="00080"),
        ),
        _malformed_vector(
            "qr-payload-empty-address-list",
            "`a` is the empty string: zero addresses, below the 1..8 minimum.",
            uri=_build_uri(addresses=""),
        ),
        _malformed_vector(
            "qr-payload-unsupported-version",
            "`v=2`: any value other than the literal `1` MUST be rejected outright (unlike the "
            "discovery TXT record's `v`, which is silently ignored).",
            uri=_build_uri(v="2"),
        ),
        _malformed_vector(
            "qr-payload-wrong-scheme",
            "The URI uses `https://pair` instead of the `tandem://` scheme.",
            uri="https://pair?v=1&fp=" + _base64url_no_padding(FP_A) + "&s=" + _base64url_no_padding(SECRET_A) + "&a=192.168.1.10&p=54321&n=Mac",
        ),
        _malformed_vector(
            "qr-payload-wrong-host",
            "The URI uses `tandem://other` instead of `tandem://pair`.",
            uri="tandem://other?v=1&fp=" + _base64url_no_padding(FP_A) + "&s=" + _base64url_no_padding(SECRET_A) + "&a=192.168.1.10&p=54321&n=Mac",
        ),
        _malformed_vector(
            "qr-payload-hostname-in-address-list",
            "`a` contains a hostname (`example.com`) instead of a literal address.",
            uri=_build_uri(addresses=["example.com"]),
        ),
        _malformed_vector(
            "qr-payload-zone-id-in-address",
            "`a` contains an IPv6 literal with a zone ID (`%en0`), which SPEC.md §2's "
            "`literal-addr` production forbids.",
            uri=_build_uri(addresses=["fe80::1%en0"]),
        ),
        _malformed_vector(
            "qr-payload-nine-addresses",
            "`a` contains 9 literal addresses, one over the 8-address maximum.",
            uri=_build_uri(addresses=nine_addresses),
        ),
        _malformed_vector(
            "qr-payload-unspecified-ipv4-address",
            "`a` contains the unspecified IPv4 address `0.0.0.0`.",
            uri=_build_uri(addresses=["0.0.0.0"]),
        ),
        _malformed_vector(
            "qr-payload-unspecified-ipv6-address",
            "`a` contains the unspecified IPv6 address `::`.",
            uri=_build_uri(addresses=["::"]),
        ),
        _malformed_vector(
            "qr-payload-broadcast-address",
            "`a` contains the IPv4 broadcast address `255.255.255.255`.",
            uri=_build_uri(addresses=["255.255.255.255"]),
        ),
        _malformed_vector(
            "qr-payload-multicast-address",
            "`a` contains a multicast IPv4 address (`224.0.0.1`).",
            uri=_build_uri(addresses=["224.0.0.1"]),
        ),
        _malformed_vector(
            "qr-payload-name-over-64-bytes",
            "`n` percent-decodes to 65 UTF-8 bytes, one over the 64-byte maximum.",
            uri=_build_uri(name=("a" * 65).encode("ascii")),
        ),
    ]

    return {
        "$schema": "./schema.json",
        "category": "qr-payload",
        "generatedBy": "tools/vectors/generate.py",
        "vectors": vectors,
    }
