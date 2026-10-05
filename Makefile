# FRTMProxy — task runner
# Il progetto Xcode è generato da project.yml via XcodeGen.
# Dopo aver modificato project.yml, esegui `make gen`.

SCHEME      ?= FRTMProxy
DESTINATION ?= platform=macOS
DERIVED     ?= .build

.DEFAULT_GOAL := help

.PHONY: help bootstrap gen build test test-bridge test-integration test-stress verify-engine run clean screenshots engine

help: ## Mostra questo aiuto
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Installa xcodegen (se assente) e genera il progetto
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
	@$(MAKE) gen

engine: ## Ripristina il motore upstream fissato e verifica il bundle
	python3 scripts/install_engine.py

gen: engine ## Rigenera FRTMProxy.xcodeproj da project.yml
	xcodegen generate

build: engine ## Compila l'app (Debug)
	xcodebuild -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' build

test: engine ## Esegue la suite di unit test
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' test

run: engine ## Builda e avvia l'app
	xcodebuild -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED) build
	open $(DERIVED)/Build/Products/Debug/$(SCHEME).app

clean: ## Pulisce gli artefatti di build
	xcodebuild -scheme $(SCHEME) clean || true
	rm -rf $(DERIVED)

screenshots: ## Cattura gli screenshot via XCUITest (richiede sessione GUI)
	./scripts/capture_screenshots.sh

verify-engine: ## Verifica integrità e versione dichiarata del motore embedded
	python3 scripts/verify_engine.py

test-bridge: ## Verifica le regole Python senza dipendenze esterne
	python3 -m unittest discover -s tests -v

test-integration: ## Verifica il proxy reale (richiede app compilata in DERIVED)
	python3 tests/integration_proxy.py --worker $(DERIVED)/Build/Products/Debug/$(SCHEME).app/Contents/MacOS/$(SCHEME)


test-stress: ## Carico locale sul motore embedded; genera artifacts/proxy-stress.json
	python3 tests/stress_proxy.py --worker $(DERIVED)/Build/Products/Debug/$(SCHEME).app/Contents/MacOS/$(SCHEME)
