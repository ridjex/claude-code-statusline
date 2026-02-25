.PHONY: help install uninstall test test-verbose test-python test-go test-rust test-all build-go build-rust bench bench-bash bench-python bench-go bench-rust bench-report profile demo check verify diagnose

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: check ## Install status line to ~/.claude/ (auto-detects best engine)
	@./install.sh

uninstall: ## Remove status line and caches
	@echo "Removing status line..."
	@rm -f ~/.claude/statusline.sh ~/.claude/statusline.py ~/.claude/cumulative-stats.sh ~/.claude/statusline.env
	@rm -rf "$${XDG_CACHE_HOME:-$$HOME/.cache}/claude-code-statusline"
	@rm -rf ~/.claude/skills/statusline
	@if [ -f ~/.claude/settings.json ] && command -v jq >/dev/null 2>&1; then \
	  jq 'del(.statusLine)' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
	    && mv ~/.claude/settings.json.tmp ~/.claude/settings.json; \
	  echo "[ok] Removed statusLine from settings.json"; \
	fi
	@echo "[ok] Uninstalled"

test: ## Run bash engine test suite
	@./tests/run-tests.sh

test-verbose: ## Run bash tests with rendered output
	@./tests/run-tests.sh -v

test-python: ## Run engine-agnostic tests against Python engine
	@./tests/test-engine.sh "python3 engines/python/statusline.py"

build-go: ## Build Go engine binary
	@cd engines/go && go build -o statusline ./cmd/statusline
	@echo "[ok] Go engine built: engines/go/statusline"

test-go: build-go ## Run engine-agnostic tests against Go engine
	@./tests/test-engine.sh "engines/go/statusline"

build-rust: ## Build Rust engine binary
	@cd engines/rust && cargo build --release
	@echo "[ok] Rust engine built: engines/rust/target/release/statusline"

test-rust: build-rust ## Run engine-agnostic tests against Rust engine
	@./tests/test-engine.sh "engines/rust/target/release/statusline"

test-parity: build-go build-rust ## Verify all engines produce identical output
	@./tests/test-parity.sh

test-all: test test-python test-go test-rust test-parity ## Run tests for all engines

bench: ## Benchmark all available engines (requires hyperfine)
	@./benchmarks/bench.sh

bench-bash: ## Benchmark bash engine only
	@./benchmarks/bench.sh bash

bench-python: ## Benchmark python engine only
	@./benchmarks/bench.sh python

bench-go: build-go ## Benchmark Go engine only
	@./benchmarks/bench.sh go

bench-rust: build-rust ## Benchmark Rust engine only
	@./benchmarks/bench.sh rust

bench-report: build-go build-rust ## Run benchmarks and generate RESULTS.md
	@./benchmarks/bench.sh --ci

profile: ## Detailed bash subprocess profiling
	@./benchmarks/profile-bash.sh

demo: ## Regenerate demo SVGs from fixtures
	@./scripts/generate-demo.sh

check: ## Check dependencies (jq, bc, git)
	@ok=true; \
	for dep in jq bc git; do \
	  if command -v $$dep >/dev/null 2>&1; then \
	    printf "  [ok] %s (%s)\n" "$$dep" "$$(command -v $$dep)"; \
	  else \
	    printf "  [!!] %s — missing (brew install %s)\n" "$$dep" "$$dep"; \
	    ok=false; \
	  fi; \
	done; \
	$$ok || exit 1

uninstall: ## Remove statusline from ~/.claude
	@bash install.sh --uninstall

diagnose: ## Check installation health and config
	@echo "=== Dependencies ==="
	@for dep in jq bc git; do \
	  if command -v $$dep >/dev/null 2>&1; then \
	    printf "  [ok] %s\n" "$$dep"; \
	  else \
	    printf "  [!!] %s — missing\n" "$$dep"; \
	  fi; \
	done
	@echo ""
	@echo "=== Scripts ==="
	@[ -x ~/.claude/statusline.sh ] && echo "  [ok] statusline.sh" || echo "  [!!] statusline.sh — missing or not executable"
	@[ -x ~/.claude/cumulative-stats.sh ] && echo "  [ok] cumulative-stats.sh" || echo "  [!!] cumulative-stats.sh — missing or not executable"
	@[ -f ~/.claude/statusline.py ] && echo "  [ok] statusline.py (python engine)" || echo "  [i ] statusline.py — not installed (using bash engine)"
	@echo ""
	@echo "=== settings.json ==="
	@if [ -f ~/.claude/settings.json ]; then \
	  TYPE=$$(jq -r '.statusLine | type' ~/.claude/settings.json 2>/dev/null); \
	  if [ "$$TYPE" = "object" ]; then \
	    CMD=$$(jq -r '.statusLine.command // "not set"' ~/.claude/settings.json); \
	    echo "  [ok] statusLine type: object"; \
	    echo "  [ok] statusLine command: $$CMD"; \
	  elif [ "$$TYPE" = "string" ]; then \
	    echo "  [!!] statusLine is a STRING (run: make install to fix)"; \
	  else \
	    echo "  [!!] statusLine not configured (run: make install)"; \
	  fi; \
	else \
	  echo "  [!!] settings.json not found (run: make install)"; \
	fi
	@echo ""
	@echo "=== Config ==="
	@if [ -f ~/.claude/statusline.env ]; then \
	  echo "  [ok] statusline.env found"; \
	  grep -c "=false" ~/.claude/statusline.env | xargs -I{} echo "  [i ] {} sections disabled"; \
	else \
	  echo "  [i ] statusline.env not found (all defaults active)"; \
	fi
	@echo ""
	@echo "=== Render test ==="
	@echo '{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":42,"total_input_tokens":5000,"total_output_tokens":1200},"cost":{"total_cost_usd":1.5,"total_duration_ms":120000,"total_api_duration_ms":80000},"workspace":{"project_dir":"/tmp","current_dir":"/tmp"}}' \
	  | ~/.claude/statusline.sh 2>/dev/null && echo "  [ok] Render successful" || echo "  [!!] Render FAILED"

verify: ## Smoke test installed statusline (run in a git repo)
	@if [ ! -x ~/.claude/statusline.sh ]; then \
	  echo "Not installed. Run: make install"; exit 1; \
	fi
	@echo '{"model":{"id":"claude-opus-4-6","display_name":"Claude Opus 4.6"},"cwd":"/tmp","context_window":{"used_percentage":42,"context_window_size":200000,"total_input_tokens":5000,"total_output_tokens":1200},"cost":{"total_cost_usd":1.5,"total_duration_ms":120000,"total_api_duration_ms":80000},"workspace":{"project_dir":"/tmp","current_dir":"/tmp"}}' \
	  | ~/.claude/statusline.sh
	@echo ""
	@echo "[ok] Status line is working"
