#!/bin/bash

# GitLab API script to list and optionally remove pipelines
# Usage: ./prune_gitlab_pipelines.sh [OPTIONS] [PROJECT_ID] [TOKEN]

# Default values (can be overridden by command line arguments)
DEFAULT_PROJECT_ID="update_or_provide_as_CLI_argument"
DEFAULT_TOKEN="update_or_provide_as_CLI_argument"
GITLAB_API_BASE="https://gitlab.com/api/v4"
DEFAULT_MAX_AGE_DAYS=7

# Initialize variables
PROJECT_ID=""
TOKEN=""
MAX_AGE_DAYS=$DEFAULT_MAX_AGE_DAYS
DRY_RUN=false
REMOVE_OLD=false
SHOW_DETAILS=false
MAX_PAGES=0
PIPELINE_STATUS=""

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [PROJECT_ID] [TOKEN]"
    echo ""
    echo "Options:"
    echo "  -h, --help                    Show this help message"
    echo "  --dry-run                     Show what would be removed without actually removing"
    echo "  --remove-old                  Remove pipelines older than specified days"
    echo "  --max-age-days DAYS           Maximum age of pipelines in days (default: $DEFAULT_MAX_AGE_DAYS)"
    echo "  --max-pages PAGES             Limit processing to specified number of pages (default: all)"
    echo "  --details                     Show detailed pipeline information"
    echo "  --status STATUS               Filter pipelines by status (success, failed, running, pending, canceled, skipped)"
    echo ""
    echo "Arguments:"
    echo "  PROJECT_ID                    GitLab project ID (default: $DEFAULT_PROJECT_ID)"
    echo "  TOKEN                         GitLab personal access token (default: uses hardcoded token)"
    echo ""
    echo "Examples:"
    echo "  $0                                                    # List all pipelines"
    echo "  $0 --dry-run --remove-old                             # Show what would be removed (7 days)"
    echo "  $0 --remove-old --max-age-days 14                    # Remove pipelines older than 14 days"
    echo "  $0 --dry-run --remove-old --max-age-days 30          # Dry run for 30 days"
    echo "  $0 --max-pages 2                                      # Process only first 2 pages"
    echo "  $0 --status failed --max-pages 5                     # Show failed pipelines (first 5 pages)"
    echo "  $0 12345678 glpat-token-here                          # Use custom project ID and token"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --remove-old)
            REMOVE_OLD=true
            shift
            ;;
        --max-age-days)
            MAX_AGE_DAYS="$2"
            shift 2
            ;;
        --max-pages)
            MAX_PAGES="$2"
            shift 2
            ;;
        --details)
            SHOW_DETAILS=true
            shift
            ;;
        --status)
            PIPELINE_STATUS="$2"
            shift 2
            ;;
        *)
            # If it's not a flag, treat as positional argument
            if [[ -z "$PROJECT_ID" ]]; then
                PROJECT_ID="$1"
            elif [[ -z "$TOKEN" ]]; then
                TOKEN="$1"
            else
                echo "Error: Unknown argument: $1"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Use defaults if not provided
PROJECT_ID="${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
TOKEN="${TOKEN:-$DEFAULT_TOKEN}"

# Validate inputs
if [[ -z "$PROJECT_ID" ]]; then
    echo "Error: PROJECT_ID is required"
    show_usage
    exit 1
fi

if [[ -z "$TOKEN" ]]; then
    echo "Error: TOKEN is required"
    show_usage
    exit 1
fi

# Validate max age days
if ! [[ "$MAX_AGE_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: --max-age-days must be a positive integer"
    exit 1
fi

# Validate max pages
if [[ "$MAX_PAGES" -ne 0 ]] && ! [[ "$MAX_PAGES" =~ ^[0-9]+$ ]]; then
    echo "Error: --max-pages must be a positive integer"
    exit 1
fi

# Validate pipeline status
if [[ -n "$PIPELINE_STATUS" ]]; then
    valid_statuses=("success" "failed" "running" "pending" "canceled" "skipped")
    if [[ ! " ${valid_statuses[@]} " =~ " ${PIPELINE_STATUS} " ]]; then
        echo "Error: Invalid pipeline status. Valid options: ${valid_statuses[*]}"
        exit 1
    fi
fi

# Setup logging
timestamp=$(date +"%Y%m%d_%H%M%S")
log_file="pipelines_${PROJECT_ID}_${timestamp}.txt"

# Function to log and print
log_echo() {
    echo "$1" | tee -a "$log_file"
}

# Function to log without printing
log_only() {
    echo "$1" >> "$log_file"
}

# Function to calculate date difference in days
date_diff_days() {
    local date1="$1"
    local date2="$2"
    
    # Convert ISO dates to epoch seconds (handle both with and without milliseconds)
    local epoch1=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${date1%.*}" "+%s" 2>/dev/null)
    local epoch2=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${date2%.*}" "+%s" 2>/dev/null)
    
    if [[ -z "$epoch1" || -z "$epoch2" ]]; then
        echo "0"
        return
    fi
    
    local diff_seconds=$(( epoch2 - epoch1 ))
    local diff_days=$(( diff_seconds / 86400 ))
    
    # Round up if there are any remaining seconds (partial day counts as full day)
    if [[ $(( diff_seconds % 86400 )) -gt 0 ]]; then
        diff_days=$(( diff_days + 1 ))
    fi
    
    echo "$diff_days"
}

# Function to delete pipeline
delete_pipeline() {
    local pipeline_id="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_echo "        [DRY RUN] Would delete pipeline: $pipeline_id"
        return 0
    fi
    
    log_echo "        Deleting pipeline: $pipeline_id"
    local delete_url="$GITLAB_API_BASE/projects/$PROJECT_ID/pipelines/$pipeline_id"
    local response=$(curl -s -X DELETE -H "PRIVATE-TOKEN: $TOKEN" "$delete_url")
    
    if [[ $? -eq 0 ]]; then
        log_echo "        ✓ Successfully deleted pipeline"
        return 0
    else
        log_echo "        ✗ Failed to delete pipeline"
        return 1
    fi
}

log_echo "Managing pipelines for project ID: $PROJECT_ID"
log_echo "Using GitLab API: $GITLAB_API_BASE"
if [[ -n "$PIPELINE_STATUS" ]]; then
    log_echo "Filter: Only showing pipelines with status '$PIPELINE_STATUS'"
fi
if [[ "$REMOVE_OLD" == true ]]; then
    log_echo "Mode: Remove pipelines older than $MAX_AGE_DAYS days"
    if [[ "$DRY_RUN" == true ]]; then
        log_echo "DRY RUN: No pipelines will be actually deleted"
    fi
else
    log_echo "Mode: List pipelines only"
fi
log_echo ""

# Get current date for age calculation
current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to process a single page of pipelines
process_page() {
    local page_num="$1"
    local pipelines_json="$2"
    local page_start_time=$(date +%s)
    
    log_echo "Processing page $page_num..."
    
    # Extract pipeline information from this page
    local pipeline_count=$(echo "$pipelines_json" | jq 'length' 2>/dev/null)
    
    if [[ -z "$pipeline_count" || "$pipeline_count" == "0" ]]; then
        log_echo "  No pipelines found on page $page_num"
        return 0
    fi
    
    local page_found_pipelines=false
    local page_removed_count=0
    local page_kept_count=0
    
    # Process each pipeline in this page
    for ((i=0; i<pipeline_count; i++)); do
        local pipeline=$(echo "$pipelines_json" | jq ".[$i]")
        local pipeline_id=$(echo "$pipeline" | jq -r '.id')
        local pipeline_status=$(echo "$pipeline" | jq -r '.status')
        local pipeline_ref=$(echo "$pipeline" | jq -r '.ref')
        local pipeline_sha=$(echo "$pipeline" | jq -r '.sha')
        local created_at=$(echo "$pipeline" | jq -r '.created_at')
        local updated_at=$(echo "$pipeline" | jq -r '.updated_at')
        local finished_at=$(echo "$pipeline" | jq -r '.finished_at // "Running"')
        local duration=$(echo "$pipeline" | jq -r '.duration // "Unknown"')
        local web_url=$(echo "$pipeline" | jq -r '.web_url')
        
        # Filter by status if specified
        if [[ -n "$PIPELINE_STATUS" && "$pipeline_status" != "$PIPELINE_STATUS" ]]; then
            continue
        fi
        
        page_found_pipelines=true
        
        log_echo "    Pipeline $pipeline_id:"
        log_echo "      Status: $pipeline_status"
        log_echo "      Branch/Tag: $pipeline_ref"
        log_echo "      SHA: ${pipeline_sha:0:8}"
        log_echo "      Created: $created_at"
        log_echo "      Updated: $updated_at"
        log_echo "      Finished: $finished_at"
        
        if [[ "$SHOW_DETAILS" == true ]]; then
            log_echo "      Duration: $duration seconds"
            log_echo "      Web URL: $web_url"
        fi
        
        # Calculate age if we have a valid created_at date
        if [[ "$created_at" != "null" && "$created_at" != "Unknown" ]]; then
            local age_days=$(date_diff_days "$created_at" "$current_date")
            log_echo "      Age: $age_days days"
            
            # Check if we should remove this pipeline
            if [[ "$REMOVE_OLD" == true && $age_days -gt $MAX_AGE_DAYS ]]; then
                log_echo "      Action: TOO OLD (> $MAX_AGE_DAYS days)"
                delete_pipeline "$pipeline_id"
                if [[ $? -eq 0 ]]; then
                    ((page_removed_count++))
                fi
            else
                log_echo "      Action: KEPT (≤ $MAX_AGE_DAYS days)"
                ((page_kept_count++))
            fi
        else
            log_echo "      Age: Unknown (cannot determine age)"
            log_echo "      Action: KEPT (unknown age)"
            ((page_kept_count++))
        fi
        
        log_echo ""
    done
    
    # Calculate processing time
    local page_end_time=$(date +%s)
    local page_processing_time=$((page_end_time - page_start_time))
    
    # Update global counters
    removed_count=$((removed_count + page_removed_count))
    kept_count=$((kept_count + page_kept_count))
    
    if [[ "$page_found_pipelines" == true ]]; then
        found_pipelines=true
    fi
    
    # Page summary
    log_echo "  Page $page_num summary:"
    log_echo "    Total pipelines: $pipeline_count"
    if [[ "$REMOVE_OLD" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_echo "    Would remove: $page_removed_count pipelines"
        else
            log_echo "    Removed: $page_removed_count pipelines"
        fi
        log_echo "    Kept: $page_kept_count pipelines"
    else
        log_echo "    Processed: $((page_removed_count + page_kept_count)) pipelines"
    fi
    log_echo "    Processing time: ${page_processing_time}s"
    log_echo ""
}

# Process pipelines page by page
log_echo "Processing pipelines page by page..."
log_echo ""

found_pipelines=false
removed_count=0
kept_count=0
current_page=1

# Process each page
while true; do
    # Check if we've reached the max pages limit
    if [[ "$MAX_PAGES" -gt 0 && "$current_page" -gt "$MAX_PAGES" ]]; then
        log_echo "Reached maximum pages limit ($MAX_PAGES)"
        break
    fi
    
    # Build URL with optional status filter
    url="$GITLAB_API_BASE/projects/$PROJECT_ID/pipelines?page=$current_page&per_page=100"
    if [[ -n "$PIPELINE_STATUS" ]]; then
        url="${url}&status=$PIPELINE_STATUS"
    fi
    
    response=$(curl -s -w "%{http_code}" -H "PRIVATE-TOKEN: $TOKEN" "$url")
    http_code="${response: -3}"
    response_body="${response%???}"
    
    if [[ $? -ne 0 ]]; then
        log_echo "Error: Failed to fetch pipelines on page $current_page"
        break
    fi
    
    # Handle rate limiting
    if [[ "$http_code" == "429" ]]; then
        log_echo "Rate limited on page $current_page, waiting 60 seconds..."
        sleep 60
        continue
    fi
    
    # Handle other HTTP errors
    if [[ "$http_code" -ge 400 ]]; then
        log_echo "HTTP error $http_code on page $current_page"
        break
    fi
    
    pipelines_json="$response_body"
    
    # Check if response is empty or invalid
    if [[ -z "$pipelines_json" || "$pipelines_json" == "null" ]]; then
        log_echo "Empty response on page $current_page, stopping"
        break
    fi
    
    # Validate JSON response
    if ! echo "$pipelines_json" | jq empty > /dev/null 2>&1; then
        log_echo "Error: Invalid JSON response on page $current_page"
        break
    fi
    
    # Check if response is empty array (end of pagination)
    page_length=$(echo "$pipelines_json" | jq 'length' 2>/dev/null)
    if [[ "$page_length" -eq 0 ]]; then
        log_echo "No more pipelines found, stopping at page $current_page"
        break
    fi
    
    # Process this page
    process_page "$current_page" "$pipelines_json"
    
    current_page=$((current_page + 1))
    
    # Add a small delay to avoid rate limiting
    sleep 0.5
done

if [[ "$found_pipelines" == false ]]; then
    log_echo "No pipelines found for this project"
    if [[ -n "$PIPELINE_STATUS" ]]; then
        log_echo "(with status filter: $PIPELINE_STATUS)"
    fi
else
    log_echo "Summary:"
    if [[ "$REMOVE_OLD" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_echo "  Would remove: $removed_count pipelines"
        else
            log_echo "  Removed: $removed_count pipelines"
        fi
        log_echo "  Kept: $kept_count pipelines"
    else
        log_echo "  Total pipelines processed: $((removed_count + kept_count))"
    fi
fi

log_echo "Script completed successfully"
log_echo "Output saved to: $log_file"
