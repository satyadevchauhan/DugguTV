#!/bin/bash

# Script to add a channel to channels.json
# Usage: ./add_channel.sh [options]
# Options:
#   -f FILE    Add channels from JSON array file
#   -h         Show help message

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Add channels to channels.json"
    echo ""
    echo "Options:"
    echo "  -f FILE    Add channels from JSON array file"
    echo "  -h         Show this help message"
    echo ""
    echo "Interactive mode:"
    echo "  $0"
    echo ""
    echo "Command line mode:"
    echo "  $0 name url logo category country language availability resolution year tags"
    exit 0
}

# Function to check and install jq if missing
check_and_install_jq() {
    if command -v jq &> /dev/null; then
        return
    fi
    OS=$(uname -s)
    case $OS in
        Linux)
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y jq
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq
            else
                echo "Please install jq manually on Linux."
                exit 1
            fi
            ;;
        Darwin)
            if command -v brew &> /dev/null; then
                brew install jq
            else
                echo "Please install Homebrew and jq."
                exit 1
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            # Windows
            echo "Downloading jq for Windows..."
            if ! command -v curl &> /dev/null; then
                echo "curl not found. Please install curl or jq manually."
                exit 1
            fi
            curl -L -o jq.exe https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe
            chmod +x jq.exe
            export PATH=$PATH:$(pwd)
            ;;
        *)
            echo "Unsupported OS: $OS. Please install jq manually."
            exit 1
            ;;
    esac
}

# Function to get input from user or parameters
get_channel_details() {
    if [ $# -eq 11 ]; then
        NAME="$1"
        URL="$2"
        LOGO="$3"
        CATEGORY="$4"
        GROUP="$5"
        COUNTRY="$6"
        LANGUAGE="$7"
        RESOLUTION="$8"
        YEAR="$9"
        STATUS="${10}"
        TAGS="${11}"
    else
        read -p "Enter channel name: " NAME
        read -p "Enter channel URL: " URL
        read -p "Enter channel logo URL: " LOGO
        read -p "Enter category: " CATEGORY
        read -p "Enter group (optional): " GROUP
        read -p "Enter country [default: US]: " COUNTRY
        read -p "Enter language [default: English]: " LANGUAGE
        read -p "Enter resolution (optional): " RESOLUTION
        read -p "Enter year (optional): " YEAR
        read -p "Enter status (true/false) [default: true]: " STATUS
        read -p "Enter tags (comma separated): " TAGS
    fi
}

# Function to validate input
validate_input() {
    if [ -z "$NAME" ] || [ -z "$URL" ] || [ -z "$CATEGORY" ]; then
        echo "Error: Name, URL, and Category are required."
        exit 1
    fi
    if [ -z "$COUNTRY" ]; then
        COUNTRY="US"
    fi
    if [ -z "$LANGUAGE" ]; then
        LANGUAGE="English"
    fi
    if [ -z "$STATUS" ]; then
        STATUS="true"
    elif [ "$STATUS" != "true" ] && [ "$STATUS" != "false" ]; then
        STATUS="true"
    fi
}

# Function to check for duplicate channel by URL
check_duplicate() {
    local json_file="channels.json"
    if jq -e ".[] | select(.url == \"$URL\")" "$json_file" >/dev/null 2>&1; then
        echo "Error: Channel with URL '$URL' already exists."
        exit 1
    fi
}

# Function to add channels from a JSON file
add_channels_from_file() {
    local input_file="$1"
    local json_file="channels.json"
    
    if [[ ! -f "$input_file" ]]; then
        echo "Error: File not found: $input_file"
        exit 1
    fi
    
    # Validate input file is valid JSON
    if ! jq empty "$input_file" 2>/dev/null; then
        echo "Error: Invalid JSON in file: $input_file"
        exit 1
    fi
    
    # Validate it's an array
    if ! jq -e 'type == "array"' "$input_file" >/dev/null 2>&1; then
        echo "Error: JSON file must contain an array of channels"
        exit 1
    fi
    
    # Filter out duplicate URLs and log them
    local added=0
    local skipped=0
    local log_file="${input_file}.import.log"
    > "$log_file"  # Clear log file
    
    jq -c '.[]' "$input_file" | while read channel; do
        local url=$(echo "$channel" | jq -r '.url')
        local name=$(echo "$channel" | jq -r '.name')
        
        if jq -e ".[] | select(.url == \"$url\")" "$json_file" >/dev/null 2>&1; then
            echo "SKIPPED: $name - URL already exists" | tee -a "$log_file"
            ((skipped++))
        else
            # Add the channel
            jq ". += [$(echo "$channel")]" "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"
            echo "ADDED: $name" | tee -a "$log_file"
            ((added++))
        fi
    done
    
    # Sort the final JSON by group then name
    jq 'sort_by(.group, .name)' "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"
    
    echo ""
    echo "Import complete!"
    echo "  Added: $added channel(s)"
    echo "  Skipped: $skipped channel(s)"
    echo "  Log saved to: $log_file"
}

# Function to add channel to JSON
add_channel() {
    local json_file="channels.json"
    local year_val
    if [ -z "$YEAR" ]; then
        year_val="null"
    else
        year_val="$YEAR"
    fi
    local new_channel=$(cat <<EOF
{
    "name": "$NAME",
    "url": "$URL",
    "logo": "$LOGO",
    "category": "$CATEGORY",
    "group": "$GROUP",
    "country": "$COUNTRY",
    "language": "$LANGUAGE",
    "resolution": "$RESOLUTION",
    "year": $year_val,
    "status": $STATUS,
    "tags": "$TAGS"
}
EOF
)

    # Add the new channel and sort by group first, then by name within each group
    jq --argjson new "$new_channel" '. + [$new] | sort_by(.group, .name)' "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"
}

# Main function
main() {
    check_and_install_jq
    
    # Check for flags
    case "${1:-}" in
        -f)
            if [[ -z "${2:-}" ]]; then
                echo "Error: -f flag requires a file path"
                echo "Usage: $0 -f <file>"
                exit 1
            fi
            add_channels_from_file "$2"
            ;;
        -h|--help)
            show_help
            ;;
        *)
            get_channel_details "$@"
            validate_input
            check_duplicate
            add_channel
            echo "Channel added successfully."
            ;;
    esac
}

main "$@"