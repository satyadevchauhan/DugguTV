#!/bin/bash

# Script to convert between JSON, CSV and M3U formats for channels

# Function to check and install jq and gawk if missing
check_and_install_jq() {
    local missing_tools=()
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if ! command -v gawk &> /dev/null; then
        missing_tools+=("gawk")
    fi
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        return
    fi
    
    OS=$(uname -s)
    case $OS in
        Linux)
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y "${missing_tools[@]}"
            elif command -v yum &> /dev/null; then
                sudo yum install -y "${missing_tools[@]}"
            else
                echo "Please install ${missing_tools[@]} manually on Linux."
                exit 1
            fi
            ;;
        Darwin)
            if command -v brew &> /dev/null; then
                brew install "${missing_tools[@]}"
            else
                echo "Please install Homebrew and ${missing_tools[@]}."
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
            echo "Unsupported OS: $OS. Please install ${missing_tools[@]} manually."
            exit 1
            ;;
    esac
}

# Function to convert JSON to M3U
json_to_m3u() {
    local json_file="$1"
    local m3u_file="$2"
    echo "#EXTM3U" > "$m3u_file"
    jq -r '.[] | objects as $ch |
        ($ch.name | ascii_downcase | gsub(" "; "")) as $id |
        (if $ch.status == null then true else $ch.status end | tostring) as $status |
        ($ch.resolution // "") as $resolution |
        ($ch.year // "") as $year |
        ($ch.logo // "") as $logo |
        ($ch.group // "") as $group |
        [
            "tvg-id=\"\($id)\"",
            "tvg-name=\"\($ch.name)\"",
            (if $logo != "" then "tvg-logo=\"\($logo)\"" else empty end),
            "tvg-category=\"\($ch.category)\"",
            (if $group != "" then "tvg-group=\"\($group)\"" else empty end),
            "tvg-country=\"\($ch.country)\"",
            "tvg-language=\"\($ch.language)\"",
            (if $resolution != "" then "tvg-resolution=\"\($resolution)\"" else empty end),
            (if $year != "" then "tvg-year=\"\($year)\"" else empty end),
            "tvg-status=\"\($status)\"",
            "tvg-tags=\"\($ch.tags)\""
        ] | join(" ") as $attrs |
        "#EXTINF:-1 \($attrs),\($ch.name)\n\($ch.url)"' "$json_file" >> "$m3u_file"
}

# Function to convert JSON to CSV
json_to_csv() {
    local json_file="$1"
    local csv_file="$2"
    echo "name|url|logo|category|group|country|language|resolution|year|status|tags" > "$csv_file"
    jq -r '.[] | "\(.name)|\(.url)|\(.logo)|\(.category)|\(.group // "")|\(.country)|\(.language)|\(.resolution)|\(.year)|\(.status)|\(.tags)"' "$json_file" | sed 's/|null/|/g; s/null//g' >> "$csv_file"
}

# Function to convert CSV to JSON
csv_to_json() {
    local csv_file="$1"
    local json_file="$2"
    awk -F'|' 'NR==1 { next } { 
        logo_val = ($3 == "" || $3 == "null") ? "null" : "\"" $3 "\"";
        year_val = ($9 == "" || $9 == "null") ? "null" : $9;
        printf "{\"name\":\"%s\",\"url\":\"%s\",\"logo\":%s,\"category\":\"%s\",\"group\":\"%s\",\"country\":\"%s\",\"language\":\"%s\",\"resolution\":\"%s\",\"year\":%s,\"status\":%s,\"tags\":\"%s\"}\n", $1, $2, logo_val, $4, $5, $6, $7, $8, year_val, $10, $11;
    }' "$csv_file" | jq -s 'sort_by(.group, .name)' > "$json_file"
}

# Function to convert M3U to JSON
m3u_to_json() {
    local m3u_file="$1"
    local json_file="$2"
    gawk '
    /^#EXTINF:/ {
        match($0, /tvg-name="([^"]*)"/, name);
        match($0, /tvg-logo="([^"]*)"/, logo);
        match($0, /tvg-category="([^"]*)"/, category);
        match($0, /tvg-group="([^"]*)"/, group);
        match($0, /tvg-country="([^"]*)"/, country);
        match($0, /tvg-language="([^"]*)"/, language);
        match($0, /tvg-status="([^"]*)"/, status);
        match($0, /tvg-tags="([^"]*)"/, tags);
        match($0, /tvg-resolution="([^"]*)"/, resolution);
        match($0, /tvg-year="([^"]*)"/, year);
        match($0, /,([^"]*)$/, display_name);
        getline url;
        status_val = (status[1] == "true") ? "true" : "false";
        logo_val = (logo[1] && logo[1] != "null") ? "\"" logo[1] "\"" : "null";
        if (year[1] && year[1] != "null") {
            year_val = year[1];
        } else {
            year_val = "null";
        }
        printf("{\"name\":\"%s\",\"url\":\"%s\",\"logo\":%s,\"category\":\"%s\",\"group\":\"%s\",\"country\":\"%s\",\"language\":\"%s\",\"resolution\":\"%s\",\"year\":%s,\"status\":%s,\"tags\":\"%s\"}\n", display_name[1], url, logo_val, category[1], group[1], country[1], language[1], resolution[1], year_val, status_val, tags[1]);
    }' "$m3u_file" | jq -s 'sort_by(.group, .name)' > "$json_file"
}

# Function to convert M3U to CSV
m3u_to_csv() {
    local m3u_file="$1"
    local csv_file="$2"
    echo "name|url|logo|category|group|country|language|resolution|year|status|tags" > "$csv_file"
    gawk '
    /^#EXTINF:/ {
        match($0, /tvg-name="([^"]*)"/, name);
        match($0, /tvg-logo="([^"]*)"/, logo);
        match($0, /tvg-category="([^"]*)"/, category);
        match($0, /tvg-group="([^"]*)"/, group);
        match($0, /tvg-country="([^"]*)"/, country);
        match($0, /tvg-language="([^"]*)"/, language);
        match($0, /tvg-status="([^"]*)"/, status);
        match($0, /tvg-tags="([^"]*)"/, tags);
        match($0, /tvg-resolution="([^"]*)"/, resolution);
        match($0, /tvg-year="([^"]*)"/, year);
        match($0, /,([^"]*)$/, display_name);
        getline url;
        status_val = (status[1] == "true") ? "true" : "false";
        year_val = (year[1] && year[1] != "null") ? year[1] : "";
        logo_val = (logo[1] && logo[1] != "null") ? logo[1] : "";
        res_val = (resolution[1] && resolution[1] != "null") ? resolution[1] : "";
        group_val = (group[1] && group[1] != "null") ? group[1] : "";
        printf("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", display_name[1], url, logo_val, category[1], group_val, country[1], language[1], res_val, year_val, status_val, tags[1]);
    }
    ' "$m3u_file" >> "$csv_file"
}

# Function to convert CSV to M3U
csv_to_m3u() {
    local csv_file="$1"
    local m3u_file="$2"
    echo "#EXTM3U" > "$m3u_file"
    tail -n +2 "$csv_file" | awk -F'|' '{
        attrs = "tvg-id=\"" $1 "\" tvg-name=\"" $1 "\" ";
        if ($3 != "") attrs = attrs "tvg-logo=\"" $3 "\" ";
        attrs = attrs "tvg-category=\"" $4 "\" ";
        if ($5 != "") attrs = attrs "tvg-group=\"" $5 "\" ";
        attrs = attrs "tvg-country=\"" $6 "\" tvg-language=\"" $7 "\" ";
        if ($8 != "") attrs = attrs "tvg-resolution=\"" $8 "\" ";
        if ($9 != "") attrs = attrs "tvg-year=\"" $9 "\" ";
        attrs = attrs "tvg-status=\"" $10 "\" tvg-tags=\"" $11 "\"";
        printf("#EXTINF:-1 %s,%s\n%s\n", attrs, $1, $2) 
    }' >> "$m3u_file"
}

# Function to detect file types and convert
convert() {
    local input_file="$1"
    local output_file="$2"
    if [[ "$input_file" == *.json ]] && [[ "$output_file" == *.m3u ]]; then
        json_to_m3u "$input_file" "$output_file"
    elif [[ "$input_file" == *.json ]] && [[ "$output_file" == *.csv ]]; then
        json_to_csv "$input_file" "$output_file"
    elif [[ "$input_file" == *.m3u ]] && [[ "$output_file" == *.json ]]; then
        m3u_to_json "$input_file" "$output_file"
    elif [[ "$input_file" == *.m3u ]] && [[ "$output_file" == *.csv ]]; then
        m3u_to_csv "$input_file" "$output_file"
    elif [[ "$input_file" == *.csv ]] && [[ "$output_file" == *.json ]]; then
        csv_to_json "$input_file" "$output_file"
    elif [[ "$input_file" == *.csv ]] && [[ "$output_file" == *.m3u ]]; then
        csv_to_m3u "$input_file" "$output_file"
    else
        echo "Unsupported conversion. Supported: json<->m3u, json<->csv, m3u<->csv"
        exit 1
    fi
}

# Main function
main() {
    check_and_install_jq
    if [ $# -ne 2 ]; then
        echo "Usage: $0 <input_file> <output_file>"
        echo "Supported conversions: json<->m3u, json<->csv, m3u<->csv"
        exit 1
    fi
    convert "$1" "$2"
    echo "Conversion completed."
}

main "$@"