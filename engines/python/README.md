# Python Engine

Drop-in replacement for the bash statusline engine. Zero external dependencies (stdlib only).

## Key differences from bash

| Aspect | Bash | Python |
|--------|------|--------|
| JSON parsing | 11+ jq subprocess calls | Single `json.load()` |
| Math | 4+ bc subprocess calls | Native `int`/`float` |
| Git | 7 subprocess calls | 7 subprocess calls (same) |
| Config | `source` env file | Manual line parsing |
| Total subprocesses | 27-35 per render | 5-8 per render |
| Render time | 30-100ms | 5-15ms |

## Usage

```bash
# Direct
cat input.json | python3 engines/python/statusline.py

# With args
cat input.json | python3 engines/python/statusline.py --no-git --no-cumulative

# Via installer (auto-detected)
make install   # installs python engine if python3 is available
```

## Output parity

The Python engine produces **byte-identical ANSI output** to the bash engine for the same input. This is verified by `tests/test-engine.sh`.

## Files

- `statusline.py` — single-file renderer (~250 LOC)
- `pyproject.toml` — project metadata (no dependencies)

## Development

```bash
make test-python    # run engine-agnostic tests against python
make bench-python   # benchmark python engine
```
