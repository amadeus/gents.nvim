# Neovim exports NVIM as a server address; only accept a command-line override.
NVIM := nvim
STYLUA ?= stylua
MINI_TEST_REV := 35c67cb7f2dc697ed0c7c06400fcf29a8a521d7d
MINI_TEST_DIR := $(CURDIR)/.deps/mini.test-$(MINI_TEST_REV)

.PHONY: test lint

test: $(MINI_TEST_DIR)/.installed
	@mkdir -p .test/cache .test/state .test/data .test/config
	XDG_CACHE_HOME="$(CURDIR)/.test/cache" \
	XDG_STATE_HOME="$(CURDIR)/.test/state" \
	XDG_DATA_HOME="$(CURDIR)/.test/data" \
	XDG_CONFIG_HOME="$(CURDIR)/.test/config" \
	MINI_TEST_DIR="$(MINI_TEST_DIR)" \
	"$(NVIM)" --headless --clean -u tests/minimal_init.lua -i NONE -c "lua dofile('tests/run.lua')"

$(MINI_TEST_DIR)/.installed:
	mkdir -p "$(MINI_TEST_DIR)"
	curl --fail --location --silent --show-error "https://github.com/nvim-mini/mini.test/archive/$(MINI_TEST_REV).tar.gz" -o "$(MINI_TEST_DIR).tar.gz"
	tar -xzf "$(MINI_TEST_DIR).tar.gz" -C "$(MINI_TEST_DIR)" --strip-components=1
	rm "$(MINI_TEST_DIR).tar.gz"
	touch "$@"

lint:
	"$(STYLUA)" --check lua plugin tests
