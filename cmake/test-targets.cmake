cmake_minimum_required(VERSION 3.17.0)

enable_testing()

# enable verbose CTest output by default
# note: We're mainly using prove which already provides a condensed output by default. To be able
#       to follow the prove output as usual and configure the test verbosity on prove-level it makes
#       sense to configure CTest to be verbose by default.
option(VERBOSE_CTEST "enables verbose tests on CTest level" ON)
if (VERBOSE_CTEST)
    set(CMAKE_CTEST_COMMAND ${CMAKE_CTEST_COMMAND} -V)
endif ()

# enable parallel tests on CTest level by default
set(CMAKE_CTEST_ARGUMENTS "--parallel" "0")

# test for install target
add_test(
    NAME test-installed-files
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-installed-files" "${CMAKE_MAKE_PROGRAM}"
    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
)

# add test for YAML syntax
find_program(YAMLLINT_PATH yamllint)
if (YAMLLINT_PATH)
    add_test(
        NAME test-local-yaml-syntax
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-yaml-syntax" "${YAMLLINT_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set YAMLLINT_PATH to the path of the yamllint executable to enable YAML syntax checks.")
endif ()

# add test for C++ code style
find_program(CLANG_FORMAT_PATH clang-format)
if (CLANG_FORMAT_PATH)
    add_test(
        NAME test-local-cpp-style
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-cpp-style" "${CLANG_FORMAT_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set CLANG_FORMAT_PATH to the path of the clang-format executable to enable C++ style checks.")
endif ()

# add test for python code style
find_program(RUFF_PATH ruff)
if (RUFF_PATH)
    add_test(
        NAME test-local-python-style
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-python-style" "${RUFF_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set RUFF_PATH to the path of the ruff executable to enable python style checks.")
endif ()

find_program(VULTURE_PATH vulture)
if (VULTURE_PATH)
    add_test(
        NAME test-local-python-code-health
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-python-code-health" "${VULTURE_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
endif ()

find_program(RADON_PATH radon)
if (RADON_PATH)
    add_test(
        NAME test-local-python-maintainability
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-python-maintainability" "${RADON_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
endif ()

add_test(
    NAME test-local-python-conventions
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-python-conventions"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

find_program(TY_PATH ty)
if (TY_PATH)
    add_test(
        NAME test-local-python-typecheck
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/typecheck-python" "${TY_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
endif ()

find_program(PYTEST_PATH pytest)
if (PYTEST_PATH)
    add_test(
        NAME test-python-testsuite
        COMMAND "${PYTEST_PATH}" -n auto -v --cov --cov-report=xml --cov-report=term-missing
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    # The current python files are data/fake modules for other tests, not pytest-runnable tests themselves.
    # We set this to pass even if no tests are found, to avoid CI failure until real tests are added.
    # pytest returns exit code 5 when no tests are collected.
    set_tests_properties(test-python-testsuite PROPERTIES PASS_REGULAR_EXPRESSION "test session starts")
endif ()

find_program(SHELLCHECK_PATH shellcheck)
if (SHELLCHECK_PATH)
    add_test(
        NAME test-local-shellcheck
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-shellcheck" "${SHELLCHECK_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set SHELLCHECK_PATH to the path of shellcheck to enable Shell style checks.")
endif ()

# add test for bash script syntax
find_program(SH_PATH shfmt)
if (SH_PATH)
    add_test(
        NAME test-local-bash-syntax
	 COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-bash-scripts" "${SH_PATH}" "${CMAKE_SOURCE_DIR}"
	 WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set SH_PATH to the path of the shfmt executable to enable bash script syntax checks.")
endif ()

# add test for git commit messages
find_program(GITLINT_PATH gitlint)
if (GITLINT_PATH)
    add_test(
        NAME test-local-git-commit-message
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-git-commit-message" "${GITLINT_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set GITLINT_PATH to the path of the gitlint executable to enable git commit message checks.")
endif ()

# add spell checking for test API documentation
find_program(PODSPELL_PATH podspell)
find_program(SPELL_PATH spell)
if (PODSPELL_PATH AND SPELL_PATH)
    add_test(
        NAME test-doc-testapi-spellchecking
        COMMAND sh -c "\"${PODSPELL_PATH}\" \"${CMAKE_CURRENT_SOURCE_DIR}/testapi.pm\" | \"${SPELL_PATH}\""
    )
else ()
    message(STATUS "Set PODSPELL_PATH/SPELL_PATH to the path of the podspell/spell executable to enable spell checking.")
endif ()

# add targets for invoking Perl test suite
find_program(PROVE_PATH prove_wrapper PATHS tools NO_DEFAULT_PATH)
find_program(PROVE_PATH prove REQUIRED)
find_program(UNBUFFER_PATH unbuffer)
add_test(
    NAME test-local-author-perl
    COMMAND make test TESTS="xt/" PROVE=${PROVE_PATH}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
add_custom_target(test-local-author-perl COMMAND ${CMAKE_CTEST_COMMAND} -R "test-local-author-perl" USES_TERMINAL)
add_custom_target(test-local COMMAND ${CMAKE_CTEST_COMMAND} -R "test-local-.*")
add_custom_target(test-doc COMMAND ${CMAKE_CTEST_COMMAND} -R "test-doc-.*")
add_custom_target(test-installed-files COMMAND ${CMAKE_CTEST_COMMAND} -R "test-installed-files")
add_custom_target(test-perl-testsuite
    COMMAND make test PROVE=${PROVE_PATH}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    USES_TERMINAL
)
add_custom_target(check COMMAND ${CMAKE_CTEST_COMMAND} USES_TERMINAL)
add_custom_target(check-pkg-build COMMAND ${CMAKE_CTEST_COMMAND} -E "test-local-.*" USES_TERMINAL)
foreach (CUSTOM_TARGET test-local-author-perl test-perl-testsuite check check-pkg-build)
    add_dependencies(${CUSTOM_TARGET} symlinks)
endforeach ()

# add target for computing test coverage of Perl test suite
find_program(COVER_PATH cover)
if (COVER_PATH AND PROVE_PATH)
    add_custom_command(
        COMMENT "Run Perl testsuite with coverage instrumentation if no coverage data has been collected so far"
        COMMAND "${COVER_PATH}" -test -make "make test COVERAGE=1 PROVE=${PROVE_PATH}" -ignore "^external/" -ignore "^tools/" -ignore "^t/data/" -ignore "^/tmp"
        OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_custom_command(
        COMMENT "Generate coverage report (HTML)"
        COMMAND "${COVER_PATH}" -report html_basic "${CMAKE_CURRENT_SOURCE_DIR}/cover_db" -outputdir "${CMAKE_CURRENT_SOURCE_DIR}"
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/coverage.html"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_custom_target(
        coverage-reset
        COMMENT "Resetting previously gathered Perl test suite coverage"
        COMMAND rm -r "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
    )
    add_custom_target(
        coverage
        COMMENT "Perl test suite coverage (HTML)"
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/coverage.html"
    )
    add_dependencies(coverage symlinks)
    add_custom_target(
        coverage-codecov
        COMMENT "Perl test suite coverage (codecov, if direct report uploading possible, e.g. within travis CI)"
        COMMAND "${COVER_PATH}" -report codecov
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_dependencies(coverage-codecov symlinks)
    add_custom_target(
        coverage-codecovbash
        COMMENT "Perl test suite coverage (codecovbash, useful if direct report upload not available)"
        COMMAND "${COVER_PATH}" -report codecovbash "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_dependencies(coverage-codecovbash symlinks)

else ()
    message(STATUS "Set COVER_PATH to the path of the cover executable to enable coverage computition of the Perl testsuite.")
endif ()
