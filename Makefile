help:
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "available targets:"
	@echo "    build ............. Generate javascript files for iOS and Android."
	@echo "    tests ............. Run all tests."
	@echo "    clean ............. Cleanup the project (temporary and generated files)."
	@echo ""
	@echo "extra targets"
	@echo "    all ............ Generate javascript files and documentation"
	@echo ""
	@echo "(c)2014-2019, Jean-Christophe Hoelt <hoelt@fovea.cc>"
	@echo ""

all: build

build: check-tsc compile test-js

compile:
	@echo "- Compiling TypeScript"
	@${NODE_MODULES}/.bin/tsc

# for backward compatibility
proprocess: compile

tests: test-js test-install
	@echo 'ok'

test-js:
	@true

test-install:
	@true

clean:
	@find . -name '*~' -exec rm '{}' ';'

todo:
	@grep -rE "TODO|XXX" src/ts src/ios
