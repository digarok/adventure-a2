GSPLUS ?= /Users/dbrock/dev/gsplus/gsplus/src/build/GSplus.app/Contents/MacOS/GSplus

.PHONY: all a2 run-a2 gfx snd clean

all: a2

gfx:
	python3 tools/gen_gfx.py

snd:
	python3 tools/tiasnd.py gen
	python3 tools/tiasnd.py wav build/snd
	python3 tools/wintune.py gen
	python3 tools/wintune.py wav build/snd/win.wav

a2:
	bash build_a2.sh

run-a2: a2
	bash tools/run.sh

clean:
	rm -rf build src/*/*_Output.txt src/a2/adventure
