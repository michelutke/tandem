#!/usr/bin/env python3
# E15-12: nmap XML parser helper.
# Usage: python3 nmap-parser.py <xml-file>
# Outputs port/proto pairs for open ports, one per line.
# Exits 1 if host is down.

import xml.etree.ElementTree as ET
import sys

def parse_nmap_xml(xml_file):
    """Parse nmap XML and print port/proto pairs for open ports."""
    try:
        tree = ET.parse(xml_file)
    except ET.ParseError as e:
        print(f"ERROR: failed to parse XML: {e}", file=sys.stderr)
        return 1

    root = tree.getroot()

    # Check if host is down
    for host in root.findall('.//host'):
        status = host.find('.//status')
        if status is not None and status.get('state') == 'down':
            print("ERROR: host is down/unreachable", file=sys.stderr)
            return 1

        # Find all open ports on this host
        for port in host.findall('.//port'):
            state = port.find('.//state')
            if state is not None and state.get('state') == 'open':
                port_num = port.get('portid')
                protocol = port.get('protocol')
                if port_num and protocol:
                    print(f"{port_num}/{protocol}")

    return 0

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: nmap-parser.py <xml-file>", file=sys.stderr)
        sys.exit(1)

    sys.exit(parse_nmap_xml(sys.argv[1]))
