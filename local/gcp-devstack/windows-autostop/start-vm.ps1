# GCP の DevStack + Harbor VM を起動する。
. "$PSScriptRoot\Load-Config.ps1"

$status = (gcloud compute instances describe $INSTANCE_NAME `
    --project=$PROJECT_ID --zone=$ZONE --format="value(status)" 2>$null)

if ($status -eq "RUNNING") {
    Write-Output "[gcp-devstack] $INSTANCE_NAME is already running"
} else {
    Write-Output "[gcp-devstack] starting $INSTANCE_NAME ..."
    gcloud compute instances start $INSTANCE_NAME --project=$PROJECT_ID --zone=$ZONE
}
