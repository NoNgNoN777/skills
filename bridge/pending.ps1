# ดูงานที่ส่งไป Antigravity ว่าตอบแล้วหรือยัง จาก sends.jsonl + ไฟล์คำตอบใน to-claude\
# ใช้:  & pending.ps1                 งานที่ยังไม่เสร็จ (ไม่มีคำตอบ / partial / need-user) ใน 7 วันล่าสุด
#       & pending.ps1 -All [-Days 30]  ทุกงานในช่วงนั้น พร้อมเวลาที่ใช้
#       & pending.ps1 -Archive [-OlderThanDays 14]  ย้ายคำตอบเก่าไป to-claude\archive\ (send ทำให้เองทุกครั้งอยู่แล้ว)
param([switch]$All, [int]$Days = 7, [switch]$Archive, [int]$OlderThanDays = 14)
. (Join-Path $PSScriptRoot 'agb-common.ps1')
if ($Archive) { Write-Output "ย้ายคำตอบเก่ากว่า $OlderThanDays วันแล้ว $(Move-AgbOldReplies $OlderThanDays) ไฟล์ -> $AgbInbox\archive\"; exit 0 }

$log = Join-Path $AgbRoot 'sends.jsonl'
if (-not (Test-Path -LiteralPath $log)) { Write-Output 'ยังไม่มีบันทึกการส่ง (sends.jsonl เริ่มบันทึกตั้งแต่รุ่น 2026.11.03)'; exit 0 }
$since = (Get-Date).AddDays(-$Days)
$rows = foreach ($line in [IO.File]::ReadAllLines($log, [Text.Encoding]::UTF8)) {
    if (-not $line.Trim()) { continue }
    try { $s = $line | ConvertFrom-Json; if (-not $s.time -or -not $s.msg_id) { continue }; $sent = [datetime]$s.time } catch { continue }
    if ($sent -lt $since) { continue }
    # คำตอบอยู่ใน to-claude\ หรือถูกย้ายไป archive\<yyyyMM ของ msg_id>\ แล้ว
    $f = Join-Path $AgbInbox "$($s.msg_id).md"
    if (-not (Test-Path -LiteralPath $f)) { $f = Join-Path $AgbInbox "archive\$($s.msg_id.Substring(0, [Math]::Min(6, $s.msg_id.Length)))\$($s.msg_id).md" }
    $status = 'ยังไม่ตอบ'; $took = ''
    $fi = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
    if ($fi -and $fi.Length -gt 0) {   # ไฟล์ 0 ไบต์ = Gemini เพิ่งเริ่มเขียน ยังนับเป็นค้าง
        try {
            $head = (Get-Content -LiteralPath $f -TotalCount 12 -Encoding UTF8) -join "`n"
            $status = if ($head -match '(?m)^status:\s*["'']?([\w-]+)') { $Matches[1] } else { '(ไม่มี status)' }
            $took = '{0:N0} นาที' -f ($fi.LastWriteTime - $sent).TotalMinutes
        } catch { $status = 'ยังไม่ตอบ' }   # ไฟล์ถูกล็อกระหว่าง Gemini เขียน
    }
    if ($status -eq 'ยังไม่ตอบ') {
        $took = 'รอมา {0:N0} นาที' -f ((Get-Date) - $sent).TotalMinutes
    }
    [pscustomobject][ordered]@{ 'ส่งเมื่อ' = $sent.ToString('MM-dd HH:mm'); msg_id = $s.msg_id; from = $s.from; status = $status; 'เวลา' = $took; conv_id = $s.conv_id }
}
if (-not $All) { $rows = @($rows | Where-Object { $_.status -in 'ยังไม่ตอบ', 'partial', 'need-user' }) }
if (-not $rows) { Write-Output $(if ($All) { "ไม่มีงานที่ส่งใน $Days วันล่าสุด" } else { "ไม่มีงานค้างใน $Days วันล่าสุด" }); exit 0 }
$rows | Format-Table -AutoSize | Out-String -Width 220
