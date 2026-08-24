# Windows の無操作時間(GetLastInputInfo)を確認し、しきい値を超えていたら
# GCP の DevStack + Harbor VM を停止する。タスクスケジューラから定期実行される想定。
# WSL には依存しない（純粋な Windows ネイティブ実装。スリープ直前に WSL の
# 軽量VMが起動していない状態でも確実に動く）。

param(
    [int]$IdleThresholdSeconds = 1800  # 30分
)

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class IdleTime {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint GetIdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        GetLastInputInfo(ref lii);
        return ((uint)Environment.TickCount - lii.dwTime) / 1000;
    }
}
'@

$idleSeconds = [IdleTime]::GetIdleSeconds()
Write-Output "[gcp-devstack] idle for $idleSeconds seconds (threshold: $IdleThresholdSeconds)"

if ($idleSeconds -ge $IdleThresholdSeconds) {
    & "$PSScriptRoot\stop-vm.ps1"
}
