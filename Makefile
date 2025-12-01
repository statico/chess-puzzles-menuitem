.PHONY: build run clean app

build:
	swift build

run: build
	swift run

app: build
	./build-app.sh release

clean:
	swift package clean
	rm -rf .build
	rm -rf "Chess Puzzles.app"
	rm -rf .iconset

