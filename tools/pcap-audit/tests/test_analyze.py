"""pytest suite for tools/pcap-audit/analyze.py (E15-04 tdd entries).

tdd:
  unit: pcapAnalyze_tls13Fixture_classifiedAsTls13ViaSupportedVersions
  unit: pcapAnalyze_tls12Fixture_classifiedAsTls12
  unit: pcapAnalyze_plaintextTcpFixture_classifiedAsPlaintextWithOffset
"""

from __future__ import annotations

from pathlib import Path

import analyze

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"


def test_pcapAnalyze_tls13Fixture_classifiedAsTls13ViaSupportedVersions():
    result = analyze.classify(FIXTURES / "tls13-handshake.pcapng")

    assert result == {"classification": "tls1.3", "negotiatedVersion": "0x0304"}


def test_pcapAnalyze_tls12Fixture_classifiedAsTls12():
    result = analyze.classify(FIXTURES / "tls12-handshake.pcapng")

    assert result["classification"] == "tls1.2"
    # The record-layer legacy version is 0x0303 in both TLS 1.2 and TLS 1.3 handshakes; the
    # classifier must not treat that as a TLS 1.3 signal.
    assert result["negotiatedVersion"] != "0x0304"


def test_pcapAnalyze_plaintextTcpFixture_classifiedAsPlaintextWithOffset():
    result = analyze.classify(FIXTURES / "plaintext-payload.pcapng")

    assert result["classification"] == "plaintext"
    assert result["frame"] > 0
    assert result["payloadOffset"] > 0


def test_pcapAnalyze_tls13Fixture_recordListIncludesHandshakeAndApplicationData():
    records = analyze.parse_records(FIXTURES / "tls13-handshake.pcapng")

    assert any(1 in r.tls_handshake_types for r in records), "expected a ClientHello frame"
    assert any(2 in r.tls_handshake_types for r in records), "expected a ServerHello frame"
    assert any(23 in r.tls_content_types for r in records), "expected an application-data record"
