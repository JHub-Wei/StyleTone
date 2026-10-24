.PHONY: generate build test swift-test format lint clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project StyleTone.xcodeproj -scheme StyleTone \
		-destination 'platform=iOS Simulator,name=iPhone 16' \
		CODE_SIGNING_ALLOWED=NO build

test: generate
	xcodebuild -project StyleTone.xcodeproj -scheme StyleTone \
		-destination 'platform=iOS Simulator,name=iPhone 16' \
		CODE_SIGNING_ALLOWED=NO test

swift-test:
	swift test

format:
	swiftformat .

lint:
	swiftlint

clean:
	rm -rf StyleTone.xcodeproj .build DerivedData
