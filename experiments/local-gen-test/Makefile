.PHONY: build test vet lint tailwind ci

build:
	go build ./cmd/agent/

test:
	go test ./...

vet:
	go vet ./...

lint:
	golangci-lint run

tailwind:
	npx tailwindcss -i web/input.css -o web/static/styles.css

ci:
	$(MAKE) build
	$(MAKE) test
	$(MAKE) vet
	$(MAKE) lint
