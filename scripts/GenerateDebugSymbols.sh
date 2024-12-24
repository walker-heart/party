#!/bin/sh

# Generate debug symbols for Firebase frameworks
find "${BUILT_PRODUCTS_DIR}" -name '*.framework' -type d | while read -r FRAMEWORK; do
    FRAMEWORK_EXECUTABLE_NAME=$(defaults read "$FRAMEWORK/Info.plist" CFBundleExecutable)
    FRAMEWORK_EXECUTABLE_PATH="$FRAMEWORK/$FRAMEWORK_EXECUTABLE_NAME"
    
    echo "Generating dSYM for $FRAMEWORK_EXECUTABLE_PATH"
    
    if [ -f "$FRAMEWORK_EXECUTABLE_PATH" ]; then
        xcrun dsymutil "$FRAMEWORK_EXECUTABLE_PATH" -o "$FRAMEWORK_EXECUTABLE_PATH.dSYM"
    fi
done 