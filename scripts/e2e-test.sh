#!/usr/bin/env bash
# End-to-end verification of the finished Contoso Claims Hub.
#   ./scripts/e2e-test.sh dev
source "$(dirname "$0")/common.sh" "${1:-dev}"

RG=$(output resourceGroupName)
API=$(output apiUrl)
PROC_APP=$(output processingFunctionAppName); require "$PROC_APP" "processing Function app"
SB=$(output serviceBusNamespaceName); require "$SB" "Service Bus namespace"
QUEUE=$(output processingQueueName)
PROC_HOST="${PROC_APP}.azurewebsites.net"   # defaultHostName is empty for Flex Consumption apps
FUNC_KEY=$(az functionapp keys list -g "$RG" -n "$PROC_APP" --query "functionKeys.default" -o tsv)
SAMPLES="$REPO_ROOT/tests"

status_of() { curl -s "$API/claims/$1" | jq -r '.status'; }

wait_for() { # claimId "Status1 Status2" [timeoutSeconds]
  local id=$1 want=" $2 " timeout=${3:-180} s=""
  for ((t=0; t<timeout; t+=5)); do
    s=$(status_of "$id"); printf '   %3ss  status=%s\n' "$t" "$s"
    [[ "$want" == *" $s "* ]] && return 0
    sleep 5
  done
  return 1
}

new_claim() { curl -s -X POST "$API/claims" -H "Content-Type: application/json" -d @"$SAMPLES/sample-claims/$1" | jq -r '.claimId'; }

upload() { # claimId file contentType
  curl -s -X POST "$API/claims/$1/documents?fileName=$(basename "$2")" \
       -H "Content-Type: $3" --data-binary @"$2" | jq -c '{status: .document.status, file: .document.fileName}'
}

step "1. Dependency health (identity-based access to Cosmos DB, Key Vault, App Configuration, Blob)"
curl -s "$API/health/dependencies" | jq '.checks[] | "\(.name): \(if .ok then "OK" else "FAIL" end) - \(.detail)"' -r

step "2. Happy path: auto claim -> documents -> validation -> processing -> approval workflow"
C1=$(new_claim auto-claim.json); echo "   claim $C1"
upload "$C1" "$SAMPLES/sample-documents/repair-estimate.pdf" application/pdf
upload "$C1" "$SAMPLES/sample-documents/damage-photo.png" image/png
wait_for "$C1" "PendingApproval" 240 && ok "Workflow waiting for approver" || fail "Did not reach PendingApproval"

echo "   workflow history (Durable Functions built-in status API):"
DT_KEY=$(az functionapp keys list -g "$RG" -n "$PROC_APP" --query "systemKeys.durabletask_extension" -o tsv)
curl -s "https://$PROC_HOST/runtime/webhooks/durabletask/instances/$C1?showHistory=true&code=$DT_KEY" \
  | jq -r '.historyEvents[]? | select(.EventType | test("TaskScheduled|TaskCompleted|TimerCreated|EventRaised")) | "     \(.Timestamp)  \(.EventType)  \(.FunctionName // .Name // "")"' 2>/dev/null \
  | head -20 || echo "     (history not available yet)"

step "3. Human approval (raise ApprovalDecision event)"
curl -s -X POST "https://$PROC_HOST/api/claims/$C1/approval?code=$FUNC_KEY" \
  -H "Content-Type: application/json" \
  -d '{"approved": true, "approver": "adjuster.kim", "comment": "Estimate matches photos"}' | jq -c .
wait_for "$C1" "Approved Rejected" 90 && ok "Final status: $(status_of "$C1")" || fail "No final decision recorded"

step "4. Invalid document is rejected by the validation Function"
C2=$(new_claim home-claim.json); echo "   claim $C2"
upload "$C2" "$SAMPLES/sample-documents/invalid-document.pdf" application/pdf
wait_for "$C2" "DocumentRejected" 120 && ok "Document rejected" || fail "Document was not rejected"
curl -s "$API/claims/$C2" | jq -r '.documents[] | "   \(.fileName): \(.status) \(.validation.problems // [])"'

step "5. Poison message -> dead-letter queue (legacy policy system offline)"
echo "   (setting ClaimsHub:LegacyPolicySystemOnline=false so the failure is reproducible)"
"$REPO_ROOT/scripts/set-appconfig.sh" "$ENV_NAME" key "ClaimsHub:LegacyPolicySystemOnline" false >/dev/null
sleep 35   # apps cache configuration for up to 30 seconds
BEFORE=$(az servicebus queue show -g "$RG" --namespace-name "$SB" -n "$QUEUE" --query "countDetails.deadLetterMessageCount" -o tsv)
C3=$(new_claim legacy-policy-claim.json); echo "   claim $C3 (DLQ count before: $BEFORE)"
upload "$C3" "$SAMPLES/sample-documents/repair-estimate.pdf" application/pdf
for ((t=0; t<180; t+=10)); do
  NOW=$(az servicebus queue show -g "$RG" --namespace-name "$SB" -n "$QUEUE" --query "countDetails.deadLetterMessageCount" -o tsv)
  printf '   %3ss  dead-letter count=%s\n' "$t" "$NOW"
  [[ "$NOW" -gt "$BEFORE" ]] && break
  sleep 10
done
[[ "$NOW" -gt "$BEFORE" ]] && ok "Message dead-lettered after 3 delivery attempts" || fail "Nothing reached the DLQ"

cat <<MSG

   To practise recovery (Lab 3.2):
     1. Fix the root cause:
        ./scripts/set-appconfig.sh $ENV_NAME key "ClaimsHub:LegacyPolicySystemOnline" true
     2. Portal > Service Bus > $SB > Queues > $QUEUE > Service Bus Explorer
        > Dead-letter tab > select the message > Re-send (Resubmit)
     3. Watch claim $C3 reach PendingApproval:
        curl -s $API/claims/$C3 | jq .status

   Claims created by this run: $C1 $C2 $C3
MSG
