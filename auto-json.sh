#!/bin/bash

# JSON Validator and Auto-corrector
# Usage: ./auto-json.sh <json_file>

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <json_file>"
    exit 1
fi

json_file="$1"
temp_file="${json_file}.tmp"

if [[ ! -f "$json_file" ]]; then
    echo "Error: File not found: $json_file"
    exit 1
fi

# Check if file is empty
if [[ ! -s "$json_file" ]]; then
    echo "Line 1: ERROR - File is empty"
    exit 1
fi

# Validate JSON syntax with jq and capture detailed errors
json_error=$(jq empty "$json_file" 2>&1)
if [[ $? -ne 0 ]]; then
    echo "JSON SYNTAX ERROR:"
    echo "$json_error"
    echo ""
    exit 1
fi

# Check for duplicate keys within same object
echo "Checking for duplicate keys..."
jq -r 'if type == "array" then
    .[] as $obj | ($obj | keys) as $keys | 
    if ($keys | length) != ($keys | unique | length) then
        ($keys - ($keys | unique)) | .[] | "ERROR - Duplicate key: \(.)"
    else empty end
else
    ($. | keys) as $keys |
    if ($keys | length) != ($keys | unique | length) then
        ($keys - ($keys | unique)) | .[] | "ERROR - Duplicate key: \(.)"
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "$line"
        echo "CORRECTION: Remove the duplicate key from the object"
    fi
done

# Check for missing required fields in array of objects
echo "Validating required fields..."
jq -r 'if type == "array" then 
    . as $arr | $arr | to_entries[] | .key as $index | .value | to_entries[] | select(.value == null or .value == "") | "Line \($index + 2): Missing or null field: \(.key)"
else 
    to_entries[] | select(.value == null or .value == "") | "Line: Missing or null field: \(.key)"
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "WARNING: $line"
    fi
done

# Validate JSON format and create corrected file
echo ""
echo "Auto-formatting JSON..."
if jq 'sort_by(.group, .name)' "$json_file" > "$temp_file" 2>/dev/null; then
    echo "✓ JSON is valid"
    echo "✓ Auto-formatted and sorted by group then name"
    mv "$temp_file" "$json_file"
    echo "✓ File updated: $json_file"
else
    echo "✗ JSON validation failed"
    rm -f "$temp_file"
    exit 1
fi
