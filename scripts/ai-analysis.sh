#!/bin/bash
set -uo pipefail

# Source utilities for logging
source /home/argocd/scripts/utils.sh

REPORT_FILE="/tmp/validation-report.json"
OUTPUT_FILE="/tmp/ai-analysis.md"

# Validate prerequisites
if [ ! -f "$REPORT_FILE" ]; then
    log_error "AI Analysis: Report file not found at $REPORT_FILE"
    exit 1
fi

if [ -z "${OPENAI_BASE_URL:-}" ]; then
    log_info "AI Analysis: OPENAI_BASE_URL not set, skipping"
    exit 1
fi

# Check if there are any errors to analyze
ERROR_COUNT=$(jq '.errors | length' "$REPORT_FILE" 2>/dev/null || echo "0")
if [ "$ERROR_COUNT" -eq 0 ]; then
    log_info "AI Analysis: No errors to analyze"
    exit 0
fi

# Configuration
API_KEY="${OPENAI_API_KEY:-NONE}"
MODEL="${OPENAI_MODEL_NAME:-openai/gpt-oss-20b}"
TIMEOUT="${OPENAI_TIMEOUT:-30}"

SYSTEM_PROMPT="You are a helpful assistant that can help me understand the errors in the Kubernetes manifest. Errors from kube-linter, kubeconform, and pluto are given in the error_message. Identify the root cause of the errors, explain why it is an error, and suggest a fix. Do not include any other text in your response other than the error analysis and fix. If you cannot identify the root cause, say so. The output should be in a format that can be displayed nicely in a web page"

USER_BASE_PROMPT="Please explain the errors in the Kubernetes manifest and suggest a fix. Here are the error message:"

REPORT_CONTENT=$(cat "$REPORT_FILE")
USER_MESSAGE="${USER_BASE_PROMPT}
${REPORT_CONTENT}"

# Build the request JSON with proper escaping using jq
REQUEST_BODY=$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$USER_MESSAGE" \
    '{
        model: $model,
        messages: [
            { role: "system", content: $system },
            { role: "user", content: $user }
        ]
    }')

log_info "AI Analysis: Calling ${OPENAI_BASE_URL}/chat/completions (model: $MODEL, timeout: ${TIMEOUT}s)"

# Call the API
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    --max-time "$TIMEOUT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "$REQUEST_BODY" \
    "${OPENAI_BASE_URL}/chat/completions" 2>&1)

CURL_EXIT=$?
if [ $CURL_EXIT -ne 0 ]; then
    log_error "AI Analysis: curl failed with exit code $CURL_EXIT"
    exit 1
fi

# Split response body and HTTP status code
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    log_error "AI Analysis: API returned HTTP $HTTP_CODE"
    log_error "AI Analysis: Response: $RESPONSE_BODY"
    exit 1
fi

# Extract the AI response content
AI_CONTENT=$(echo "$RESPONSE_BODY" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

if [ -z "$AI_CONTENT" ]; then
    log_error "AI Analysis: No content in API response"
    exit 1
fi

# Write the AI analysis to the output file
echo "$AI_CONTENT" > "$OUTPUT_FILE"
log_info "AI Analysis: Successfully generated analysis ($(wc -c < "$OUTPUT_FILE" | tr -d ' ') bytes)"
