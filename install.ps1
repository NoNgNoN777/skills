# ติดตั้งจาก repo นี้ลงเครื่อง ใช้ตัวติดตั้งตัวเดียวกับไฟล์ติดตั้งไฟล์เดียวใน dist\ (ข้ามไฟล์ที่เหมือนเดิม · สำรองไฟล์ที่ต่างไว้ใน ~/.agent-bridge/backup/)
# ใช้:  & .\install.ps1 [-DryRun] [-Root <โฟลเดอร์ทดสอบแทน $HOME>]
# แก้ไฟล์ต้นฉบับแล้ว ให้รัน python -I tools/build.py ก่อน เพื่อให้ dist\ เป็นรุ่นล่าสุด
param([switch]$DryRun, [string]$Root = $HOME)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'tools\install-agb.ps1') -Installer (Join-Path $PSScriptRoot 'dist\ai-bridge-installer.md') -DryRun:$DryRun -Root $Root
