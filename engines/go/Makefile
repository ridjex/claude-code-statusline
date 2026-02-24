.PHONY: build clean test

build: ## Build the statusline binary
	go build -o statusline ./cmd/statusline

clean: ## Remove built binary
	rm -f statusline

test: ## Run Go unit tests
	go test ./...
