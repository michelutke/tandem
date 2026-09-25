import sys
from pathlib import Path

# capture.sh and analyze.py are plain scripts, not an installed package; make analyze importable
# as `analyze` from the test suite.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
