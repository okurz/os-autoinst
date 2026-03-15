# This Makefile manages Rust and Perl components of os-autoinst

.PHONY: all
all: build-rust ## Build all components

.PHONY: build-rust
build-rust: ## Build the Rust core component
	cd rust/os-autoinst-core && cargo build --release
	cp rust/os-autoinst-core/target/release/libos_autoinst_core.so rust/os-autoinst-core/os_autoinst_core.so
	ln -sf rust/os-autoinst-core/target/release/videoencoder videoencoder
	ln -sf rust/os-autoinst-core/target/release/snd2png snd2png
	mkdir -p debugviewer
	ln -sf ../script/debugviewer.py debugviewer/debugviewer
	chmod +x script/debugviewer.py

.PHONY: help
help: ## Display this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: setup-hooks
setup-hooks: ## Install pre-commit git hooks
	pre-commit install --install-hooks -t commit-msg -t pre-commit

.PHONY: check
check: ## Run tests
	prove -r t xt

.PHONY: update-deps
update-deps: ## Update project dependencies
	./tools/update-deps --cpanfile --specfile dist/rpm/os-autoinst.spec
