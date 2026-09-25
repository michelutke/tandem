"""pytest suite for protocol/vectors/qr-payload.json (E01-21 tdd entries).

Each test re-parses the committed manifest's `input.uri` through `qr_payload.parse_pair_uri` (the
reference parser for SPEC.md §2's `pair-uri` grammar) and checks the result against the manifest's
`expected` / `expectedError`, exactly as a conformance runner on either platform would.
"""

from __future__ import annotations

from typing import Any

import qr_payload as qp
import vector_schema

MANIFEST_PATH = vector_schema.VECTORS_DIR / "qr-payload.json"


def _load_manifest() -> dict[str, Any]:
    return vector_schema.load_manifest(MANIFEST_PATH)


def _vectors_by_id(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {v["id"]: v for v in manifest["vectors"]}


def test_qrPayloadVector_wellFormedPayload_parsesToExpectedFields():
    manifest = _load_manifest()
    valid_vectors = [v for v in manifest["vectors"] if "expected" in v]

    assert len(valid_vectors) >= 3

    address_list_lengths = set()
    for vector in valid_vectors:
        result = qp.parse_pair_uri(vector["input"]["uri"])
        expected = vector["expected"]

        assert result.accepted
        assert result.version == expected["version"]
        assert result.fingerprint.hex() == expected["fingerprintHex"]
        assert result.secret.hex() == expected["secretHex"]
        assert list(result.addresses) == expected["addresses"]
        assert result.port == expected["port"]
        assert result.name.hex() == expected["nameHex"]
        address_list_lengths.add(len(expected["addresses"]))

    assert len(address_list_lengths) >= 2, "valid vectors MUST vary the address-list length"


def test_qrPayloadVector_missingRequiredField_expectedErrorNamesField():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-missing-field"]

    result = qp.parse_pair_uri(vector["input"]["uri"])

    assert not result.accepted
    assert result.error == "missingRequiredField"
    assert vector["expectedError"] == "missingRequiredField"
    assert vector["input"]["invalidField"] == result.field
    assert result.field in qp.REQUIRED_FIELDS
    assert f"{result.field}=" not in vector["input"]["uri"].split("?", 1)[1]


def test_qrPayloadVector_duplicatedField_expectedErrorDuplicatedField():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-duplicated-field"]

    result = qp.parse_pair_uri(vector["input"]["uri"])
    query = vector["input"]["uri"].split("?", 1)[1]

    assert not result.accepted
    assert result.error == "duplicatedField"
    assert vector["expectedError"] == "duplicatedField"
    field = vector["input"]["invalidField"]
    assert sum(1 for pair in query.split("&") if pair.split("=", 1)[0] == field) == 2


def test_qrPayloadVector_paddedBase64url_expectedErrorInvalidEncoding():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-padded-base64url-fp"]

    result = qp.parse_pair_uri(vector["input"]["uri"])

    assert not result.accepted
    assert result.error == "invalidEncoding"
    assert vector["expectedError"] == "invalidEncoding"
    assert "=" in vector["input"]["uri"].split("fp=", 1)[1].split("&", 1)[0]


def test_qrPayloadVector_fingerprintNot32Bytes_expectedErrorInvalidFingerprint():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-fingerprint-wrong-length"]

    result = qp.parse_pair_uri(vector["input"]["uri"])

    assert not result.accepted
    assert result.error == "invalidFingerprint"
    assert vector["expectedError"] == "invalidFingerprint"


def test_qrPayloadVector_secretNot16Bytes_expectedErrorInvalidSecret():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-secret-wrong-length"]

    result = qp.parse_pair_uri(vector["input"]["uri"])

    assert not result.accepted
    assert result.error == "invalidSecret"
    assert vector["expectedError"] == "invalidSecret"


def test_qrPayloadVector_portOutOfRange_expectedErrorInvalidPort():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    for vector_id in ("qr-payload-port-zero", "qr-payload-port-too-large", "qr-payload-port-leading-zero"):
        vector = by_id[vector_id]
        result = qp.parse_pair_uri(vector["input"]["uri"])
        assert not result.accepted, vector_id
        assert result.error == "invalidPort", vector_id
        assert vector["expectedError"] == "invalidPort", vector_id


def test_qrPayloadVector_emptyAddressList_expectedErrorInvalidAddress():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-empty-address-list"]

    result = qp.parse_pair_uri(vector["input"]["uri"])

    assert not result.accepted
    assert result.error == "invalidAddress"
    assert vector["expectedError"] == "invalidAddress"


def test_qrPayloadVector_unsupportedVersion_expectedErrorUnsupportedVersion():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-unsupported-version"]

    result = qp.parse_pair_uri(vector["input"]["uri"])

    assert not result.accepted
    assert result.error == "unsupportedVersion"
    assert vector["expectedError"] == "unsupportedVersion"
    assert "v=2" in vector["input"]["uri"]


def test_qrPayloadVector_wrongSchemeOrHost_rejected():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    scheme_vector = by_id["qr-payload-wrong-scheme"]
    result = qp.parse_pair_uri(scheme_vector["input"]["uri"])
    assert not result.accepted
    assert result.error == "invalidScheme"
    assert scheme_vector["expectedError"] == "invalidScheme"
    assert scheme_vector["input"]["uri"].startswith("https://")

    host_vector = by_id["qr-payload-wrong-host"]
    result = qp.parse_pair_uri(host_vector["input"]["uri"])
    assert not result.accepted
    assert result.error == "invalidHost"
    assert host_vector["expectedError"] == "invalidHost"
    assert host_vector["input"]["uri"].startswith("tandem://other")


def test_qrPayloadVector_hostnameInAddressList_expectedErrorInvalidAddress():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-hostname-in-address-list"]

    result = qp.parse_pair_uri(vector["input"]["uri"])

    assert not result.accepted
    assert result.error == "invalidAddress"
    assert vector["expectedError"] == "invalidAddress"
    assert "example.com" in vector["input"]["uri"]


def test_qrPayloadVector_nineAddresses_expectedErrorTooManyAddresses():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-nine-addresses"]

    result = qp.parse_pair_uri(vector["input"]["uri"])
    query = vector["input"]["uri"].split("a=", 1)[1].split("&", 1)[0]

    assert len(query.split(",")) == 9
    assert not result.accepted
    assert result.error == "tooManyAddresses"
    assert vector["expectedError"] == "tooManyAddresses"


def test_qrPayloadVector_forbiddenAddressCategories_expectedErrorInvalidAddress():
    manifest = _load_manifest()
    by_id = _vectors_by_id(manifest)

    for vector_id in (
        "qr-payload-zone-id-in-address",
        "qr-payload-unspecified-ipv4-address",
        "qr-payload-unspecified-ipv6-address",
        "qr-payload-broadcast-address",
        "qr-payload-multicast-address",
    ):
        vector = by_id[vector_id]
        result = qp.parse_pair_uri(vector["input"]["uri"])
        assert not result.accepted, vector_id
        assert result.error == "invalidAddress", vector_id
        assert vector["expectedError"] == "invalidAddress", vector_id


def test_qrPayloadVector_macNameOver64Bytes_expectedErrorInvalidName():
    manifest = _load_manifest()
    vector = _vectors_by_id(manifest)["qr-payload-name-over-64-bytes"]

    result = qp.parse_pair_uri(vector["input"]["uri"])
    import urllib.parse

    percent_decoded = urllib.parse.unquote_to_bytes(vector["input"]["uri"].split("n=", 1)[1])

    assert len(percent_decoded) == 65
    assert not result.accepted
    assert result.error == "invalidName"
    assert vector["expectedError"] == "invalidName"


def test_qrPayloadVectorGenerator_runTwice_outputByteIdentical():
    assert qp.generate_qr_payload_vectors() == qp.generate_qr_payload_vectors()


def test_qrPayloadVectorManifest_committedFile_validatesAgainstSchema():
    assert MANIFEST_PATH.exists(), f"missing committed manifest: {MANIFEST_PATH}"
    manifest = vector_schema.load_manifest(MANIFEST_PATH)
    assert vector_schema.validate_manifest(manifest) == []
    assert manifest["category"] == "qr-payload"
