# FRTMProxy — task runner
# Il progetto Xcode è generato da project.yml via XcodeGen.
# Dopo aver modificato project.yml, esegui `make gen`.

SCHEME      ?= FRTMProxy
DESTINATION ?= platform=macOS
DERIVED     ?= .build

.DEFAULT_GOAL := help

.PHONY: help bootstrap gen build test run clean screenshots

help: ## Mostra questo aiuto
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Installa xcodegen (se assente) e genera il progetto
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
	@$(MAKE) gen

gen: ## Rigenera FRTMProxy.xcodeproj da project.yml
	xcodegen generate

build: ## Compila l'app (Debug)
	xcodebuild -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' build

test: ## Esegue la suite di unit test
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' test

run: ## Builda e avvia l'app
	xcodebuild -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED) build
	open $(DERIVED)/Build/Products/Debug/$(SCHEME).app

clean: ## Pulisce gli artefatti di build
	xcodebuild -scheme $(SCHEME) clean || true
	rm -rf $(DERIVED)

screenshots: ## Cattura gli screenshot 1.7.0 via XCUITest (richiede sessione GUI)
	./scripts/capture_screenshots.sh
