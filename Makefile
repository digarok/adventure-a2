GSPLUS ?= /Users/dbrock/dev/gsplus/gsplus/src/build/GSplus.app/Contents/MacOS/GSplus

.PHONY: all a2 gs run-a2 run-gs gfx clean

all: a2 gs

gfx:
	python3 tools/gen_gfx.py

a2:
	bash build_a2.sh

gs:
	bash build_gs.sh

run-a2: a2
	bash tools/run.sh a2

run-gs: gs
	bash tools/run.sh gs

clean:
	rm -rf build src/*/*_Output.txt src/a2/adventure src/gs/adventure
