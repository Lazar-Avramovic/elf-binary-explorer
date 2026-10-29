PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: all test install clean

all:
	bash build.sh

test: all
	bash tests/run_tests.sh

install: all
	PREFIX="$(PREFIX)" DESTDIR="$(DESTDIR)" bash install.sh

clean:
	rm -rf build
