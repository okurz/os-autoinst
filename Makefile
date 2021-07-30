# This is a convenience Makefile wrapping cmake calls
# All targets should be defined in CMake

build := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))build
comma := ,
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
TESTS ?= t/
PROVE ?= tools/prove_wrapper
PROVE_ARGS ?=
.PHONY: test
test: test-non-perl test-perl-internal ## Run all tests

.PHONY: test-perl-internal
test-perl-internal:
	$(MAKE) test-perl TESTS="$(if $(subst t/,,$(TESTS)),$(TESTS),t/ xt/)"

.PHONY: test-perl
test-perl: all
	OS_AUTOINST_BUILD_DIRECTORY=. OS_AUTOINST_MAKE_TOOL=make \
	PERL5LIB=".:ppmclibs/blib/lib:ppmclibs/blib/arch/auto/tinycv:${PERL5LIB}" \
	$(if $(COVERAGE),PERL5OPT="-Iexternal/os-autoinst-common/lib -MTest::CheckGitStatus -It/lib -MCoverageWorkaround -MDevel::Cover=-db$(comma)cover_db$(comma)-ignore$(comma)^external/$(comma)-ignore$(comma)^tools/$(comma)-ignore$(comma)^t/data/$(comma)-ignore$(comma)^/tmp $(PERL5OPT)") \
	${PROVE} ${PROVE_ARGS} -I. -r ${TESTS}

.PHONY: test-non-perl
test-non-perl: all
	ninja -C ${build} test-ctest
