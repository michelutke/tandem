import sys
from pathlib import Path

# tools/vectors/generate.py and vector_schema.py are plain scripts, not an installed package;
# make them importable as `generate` / `vector_schema` from the test suite.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
