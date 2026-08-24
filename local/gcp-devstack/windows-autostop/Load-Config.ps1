# config.env (KEY="VALUE" 形式) を読み込み、環境変数として展開する。
# stop-vm.ps1 / start-vm.ps1 / check-idle-and-stop.ps1 から dot-source して使う。

$ConfigPath = Join-Path $PSScriptRoot "config.env"

if (-not (Test-Path $ConfigPath)) {
    Write-Error "config.env が見つかりません: $ConfigPath`nconfig.env.example をコピーして terraform output の値を入力してください"
    exit 1
}

Get-Content $ConfigPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"?([^"]*)"?$') {
        # dot-source されて呼び出し元スクリプトのスコープで実行される前提。
        # 明示的なスコープ指定はせず、呼び出し元から $PROJECT_ID 等がそのまま見える形にする
        Set-Variable -Name $Matches[1] -Value $Matches[2]
    }
}

if (-not $PROJECT_ID -or -not $ZONE -or -not $INSTANCE_NAME) {
    Write-Error "config.env に PROJECT_ID / ZONE / INSTANCE_NAME を設定してください"
    exit 1
}
