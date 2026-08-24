# GCP の DevStack + Harbor VM を停止する。
# 既に停止済み/停止中なら何もしない。
. "$PSScriptRoot\Load-Config.ps1"

$status = (gcloud compute instances describe $INSTANCE_NAME `
    --project=$PROJECT_ID --zone=$ZONE --format="value(status)" 2>$null)

if ($status -eq "RUNNING") {
    Write-Output "[gcp-devstack] stopping $INSTANCE_NAME ..."
    gcloud compute instances stop $INSTANCE_NAME --project=$PROJECT_ID --zone=$ZONE --quiet
} else {
    Write-Output "[gcp-devstack] $INSTANCE_NAME is already '$status', nothing to do"
}
