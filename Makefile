.PHONY: help install uninstall test test-verbose demo check verify

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: check ## Install status line to ~/.claude/
	@./install.sh

uninstall: ## Remove status line and caches
	@echo "Removing status line..."
	@rm -f ~/.claude/statusline.sh ~/.claude/cumulative-stats.sh
	@rm -rf "$${XDG_CACHE_HOME:-$$HOME/.cache}/claude-code-statusline"
	@if [ -f ~/.claude/settings.json ] && command -v jq >/dev/null 2>&1; then \
	  jq 'del(.statusLine)' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
	    && mv ~/.claude/settings.json.tmp ~/.claude/settings.json; \
	  echo "[ok] Removed statusLine from settings.json"; \
	fi
	@echo "[ok] Uninstalled"

test: ## Run test suite (54 assertions)
	@./tests/run-tests.sh

test-verbose: ## Run tests with rendered output
	@./tests/run-tests.sh -v

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

verify: ## Smoke test installed statusline (run in a git repo)
	@if [ ! -x ~/.claude/statusline.sh ]; then \
	  echo "Not installed. Run: make install"; exit 1; \
	fi
	@echo '{"model":{"id":"claude-opus-4-6","display_name":"Claude Opus 4.6"},"cwd":"/tmp","context_window":{"used_percentage":42,"context_window_size":200000,"total_input_tokens":5000,"total_output_tokens":1200},"cost":{"total_cost_usd":1.5,"total_duration_ms":120000,"total_api_duration_ms":80000},"workspace":{"project_dir":"/tmp","current_dir":"/tmp"}}' \
	  | ~/.claude/statusline.sh
	@echo ""
	@echo "[ok] Status line is working"
