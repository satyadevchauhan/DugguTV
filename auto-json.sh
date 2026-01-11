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
    echo "  $json_error"
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
        echo "  $line"
        echo "  CORRECTION: Remove the duplicate key from the object"
    fi
done

# Check for duplicate URLs
echo "Checking for duplicate URLs..."
jq -r 'if type == "array" then
    map(.url) as $urls |
    $urls | to_entries[] | .value as $url | .key as $index |
    ($urls | map(select(. == $url)) | length) as $count |
    if $count > 1 then
        "ERROR - Duplicate URL found at index \($index): \($url) (appears \($count) times)"
    else empty end
else
    if .url then
        "Single object: URL = \(.url)"
    else empty end
end' "$json_file" 2>/dev/null | sort | uniq | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Define required model fields
REQUIRED_FIELDS=("name" "url" "logo" "category" "group" "country" "language" "resolution" "status" "tags")

# Check for missing required fields in array of objects
echo "Validating required fields..."
jq -r --arg fields "$(printf '%s\n' "${REQUIRED_FIELDS[@]}" | jq -R . | jq -s .)" 'if type == "array" then 
    . as $arr | $arr | to_entries[] | .key as $index | .value as $obj | 
    ($fields | fromjson) as $required |
    ($required - ($obj | keys)) as $missing |
    if ($missing | length) > 0 then
        "Line \($index + 2): Missing required fields: \($missing | join(", "))"
    else empty end
else 
    ($fields | fromjson) as $required |
    ($required - (. | keys)) as $missing |
    if ($missing | length) > 0 then
        "Missing required fields: \($missing | join(", "))"
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  ERROR: $line"
    fi
done

# Check for null or empty values in required fields
echo "Validating required fields are not null/empty..."
jq -r --arg fields "$(printf '%s\n' "${REQUIRED_FIELDS[@]}" | jq -R . | jq -s .)" 'if type == "array" then 
    . as $arr | $arr | to_entries[] | .key as $index | .value | 
    ($fields | fromjson) as $required |
    (to_entries[] | select(($required | index(.key)) and (.value == null or .value == "")) | .key) as $invalid |
    "Line \($index + 2): Required field is null or empty: \($invalid)"
else 
    ($fields | fromjson) as $required |
    (to_entries[] | select(($required | index(.key)) and (.value == null or .value == "")) | .key) as $invalid |
    "Required field is null or empty: \($invalid)"
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  ERROR: $line"
    fi
done

# Check for URL format validation
echo "Validating URL formats..."
jq -r 'if type == "array" then
    .[] as $obj | ($obj | keys_unsorted | index("url")) as $idx | 
    if $idx then
        if ($obj.url | test("^https?://")) then empty
        else "ERROR - Invalid URL format: \($obj.url)"
        end
    else empty end
else
    if .url then
        if (.url | test("^https?://")) then empty
        else "ERROR - Invalid URL format: \(.url)"
        end
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Check for logo URL format validation
echo "Validating logo URL formats..."
jq -r 'if type == "array" then
    .[] as $obj | ($obj | keys_unsorted | index("logo")) as $idx | 
    if $idx then
        if ($obj.logo | test("^https?://")) then empty
        else "ERROR - Invalid logo URL format: \($obj.logo)"
        end
    else empty end
else
    if .logo then
        if (.logo | test("^https?://")) then empty
        else "ERROR - Invalid logo URL format: \(.logo)"
        end
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Check for duplicate names
echo "Checking for duplicate channel names..."
jq -r 'if type == "array" then
    map(.name) as $names |
    $names | to_entries[] | .value as $name | .key as $index |
    ($names | map(select(. == $name)) | length) as $count |
    if $count > 1 then
        "ERROR - Duplicate name: \($name) (appears \($count) times)"
    else empty end
else empty end' "$json_file" 2>/dev/null | sort | uniq | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Check for valid resolution format (480p, 720p, 1080p, 2160p, etc.)
echo "Validating resolution formats..."
jq -r 'if type == "array" then
    .[] as $obj | ($obj | keys_unsorted | index("resolution")) as $idx |
    if $idx then
        if ($obj.resolution | test("^[0-9]+(p|i)$")) then empty
        else "ERROR - Invalid resolution format: \($obj.resolution) (should be like 720p, 1080p, etc.)"
        end
    else empty end
else
    if .resolution then
        if (.resolution | test("^[0-9]+(p|i)$")) then empty
        else "ERROR - Invalid resolution format: \(.resolution) (should be like 720p, 1080p, etc.)"
        end
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Check for valid country code (ISO 3166-1 alpha-2)
echo "Validating country codes..."
jq -r 'if type == "array" then
    .[] as $obj | ($obj | keys_unsorted | index("country")) as $idx |
    if $idx then
        if ($obj.country | test("^[A-Z]{2}$")) then empty
        else "ERROR - Invalid country code: \($obj.country) (should be 2-letter ISO code like IN, US, etc.)"
        end
    else empty end
else
    if .country then
        if (.country | test("^[A-Z]{2}$")) then empty
        else "ERROR - Invalid country code: \(.country) (should be 2-letter ISO code like IN, US, etc.)"
        end
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Check for status type (must be boolean, not string)
echo "Validating status field types..."
jq -r 'if type == "array" then
    .[] as $obj |
    if $obj.status != null then
        if ($obj.status | type) == "boolean" then empty
        else "ERROR - Status must be boolean (true/false), got: \($obj.status | type) for \($obj.name)"
        end
    else empty end
else
    if .status != null then
        if (.status | type) == "boolean" then empty
        else "ERROR - Status must be boolean (true/false), got: \(.status | type)"
        end
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Check for trailing/leading spaces in string fields
echo "Checking for leading/trailing spaces..."
jq -r 'if type == "array" then
    .[] as $obj | ($obj | keys_unsorted | to_entries[] | select(.value | type == "string") | .value) as $key |
    if ($obj[$key] | test("^ | $")) then
        "WARNING - Field \($key) has leading/trailing spaces: \"\($obj[$key])\""
    else empty end
else
    (.keys_unsorted[] | select((. | type) == "string")) as $key |
    if (.[$key] | test("^ | $")) then
        "WARNING - Field \($key) has leading/trailing spaces: \"\(.[$key])\""
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Check for year field type (must be number or null)
echo "Validating year field types..."
jq -r 'if type == "array" then
    .[] as $obj | ($obj | keys_unsorted | index("year")) as $idx |
    if $idx and ($obj.year != null) then
        if ($obj.year | type) == "number" then empty
        else "ERROR - Year must be a number or null, got: \($obj.year | type)"
        end
    else empty end
else
    if .year and (.year != null) then
        if (.year | type) == "number" then empty
        else "ERROR - Year must be a number or null, got: \(.year | type)"
        end
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
    fi
done

# Check for tags format (comma-separated, no extra spaces)
echo "Validating tags format..."
jq -r 'if type == "array" then
    .[] as $obj | ($obj | keys_unsorted | index("tags")) as $idx |
    if $idx then
        if ($obj.tags | test("^[^,]+(,[^,\\s]+)*$")) then empty
        else "WARNING - Tags format issue (should be comma-separated without spaces): \($obj.tags)"
        end
    else empty end
else
    if .tags then
        if (.tags | test("^[^,]+(,[^,\\s]+)*$")) then empty
        else "WARNING - Tags format issue (should be comma-separated without spaces): \(.tags)"
        end
    else empty end
end' "$json_file" 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        echo "  $line"
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
