# GCP DevStack + Harbor VM のアイドル自動停止用タスクを Windows タスクスケジューラに登録する。
# PowerShell を「管理者として実行」した状態で実行すること。
#
# 登録される2つのタスク:
#   1. GCPDevStackIdleCheck  - 10分おきに check-idle-and-stop.ps1 を実行（主たる自動停止手段）
#   2. GCPDevStackSleepStop  - PC がスリープに入る瞬間に即座に stop-vm.ps1 を実行
#      （補助手段。スリープ移行が速くタスクが完了しない場合もあるため、
#       確実性はアイドル監視タスクの方が高い）
#
# 削除するには:
#   schtasks /delete /tn GCPDevStackIdleCheck /f
#   schtasks /delete /tn GCPDevStackSleepStop /f

$ErrorActionPreference = "Stop"

# config.env が存在することだけ先に確認しておく（未設定のまま登録しても動かないため）
. "$PSScriptRoot\Load-Config.ps1" | Out-Null

$idleScript = Join-Path $PSScriptRoot "check-idle-and-stop.ps1"
$stopScript = Join-Path $PSScriptRoot "stop-vm.ps1"

$idleAction = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$idleScript`""
$stopAction = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$stopScript`""

Write-Output "Registering GCPDevStackIdleCheck (every 10 minutes) ..."
schtasks /create /tn "GCPDevStackIdleCheck" /tr $idleAction /sc minute /mo 10 /f

Write-Output "Registering GCPDevStackSleepStop (on sleep event) ..."
$eventQuery = "*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=42]]"
schtasks /create /tn "GCPDevStackSleepStop" /tr $stopAction /sc onevent /ec System /mo $eventQuery /f

Write-Output ""
Write-Output "登録完了。確認: schtasks /query /tn GCPDevStackIdleCheck"
Write-Output "手動テスト:       schtasks /run /tn GCPDevStackIdleCheck"
Write-Output "削除:             schtasks /delete /tn GCPDevStackIdleCheck /f"
Write-Output "                   schtasks /delete /tn GCPDevStackSleepStop /f"
