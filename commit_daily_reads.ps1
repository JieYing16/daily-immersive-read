$repo = "D:\GitHub\daily-immersive-read"
$files = @("daily_reads.md", "index.html")

Set-Location $repo

$status = git status --porcelain $file 2>&1
if ($status) {
    git add $files
    $date = Get-Date -Format "yyyy-MM-dd"
    git commit -m "chore: daily reads $date"
    git push origin main
} else {
    Write-Output "No changes to $file — nothing to commit."
}
