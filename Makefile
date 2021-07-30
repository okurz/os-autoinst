# This is a convenience Makefile wrapping cmake calls
# All targets should be defined in CMake

build := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))build
.PHONY: all
all: build/build.ninja ## Build all and create symlinks
	ninja -C ${build} symlinks

.PHONY: help
help: build/build.ninja ## Display this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Internal targets from CMake/Ninja:"
	@ninja -C ${build} help

# empty default to ensure build dir is created when make called with arguments
Makefile: ;
%: build/build.ninja
	ninja -C ${build} $@

build/build.ninja:
	@mkdir -p ${build}
	@cmake -B ${build} -S . -G Ninja
.PHONY: setup-hooks
setup-hooks: ## Install pre-commit git hooks
	pre-commit install --install-hooks -t commit-msg -t pre-commit

# Devel::Cover works best with a simple "test" target in a top-level Makefile
# Call "check" for all tests and checks
TESTS ?= t/
PROVE ?= tools/prove_wrapper
.PHONY: test
test: all
	OS_AUTOINST_BUILD_DIRECTORY=. OS_AUTOINST_MAKE_TOOL=make \
	PERL5LIB=".:ppmclibs/blib/lib:ppmclibs/blib/arch/auto/tinycv:${PERL5LIB}" \
	$(if $(COVERAGE),PERL5OPT="-Iexternal/os-autoinst-common/lib -MTest::CheckGitStatus -It/lib -MCoverageWorkaround $(PERL5OPT)") \
	${PROVE} -I. -r ${TESTS}
