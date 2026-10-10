# Apple 앱 내 구입 키를 Netlify 환경 변수로 등록한다(서버 verify-subscription의 iOS 검증용).
# 비밀 값은 이 파일에 없다. F:\keys\PDF_daeri 에서 읽어 Netlify에 올릴 뿐이며 화면에 출력하지 않는다.
# 실행: 저장소 루트(F:\PDF_daeri)에서  powershell -ExecutionPolicy Bypass -File tool\set_netlify_apple_iap_env.ps1
$ErrorActionPreference = 'Stop'
$keys = 'F:\keys\PDF_daeri'
$envText = Get-Content -Raw -Encoding UTF8 (Join-Path $keys '.env')
$m = [regex]::Match($envText, '(?s)app\s*내\s*구입.*?issuer\s*ID\s*[:：]\s*(\S+).*?키\s*ID\s*[:：]\s*(\S+)', 'IgnoreCase')
if (-not $m.Success) { throw '.env에서 "app 내 구입" 블록(issuer ID, 키 ID)을 찾지 못했습니다.' }
$issuer = $m.Groups[1].Value
$keyId = $m.Groups[2].Value
$p8 = Get-ChildItem $keys -Filter 'SubscriptionKey_*.p8' | Select-Object -First 1
if (-not $p8) { throw 'SubscriptionKey_*.p8 파일을 찾지 못했습니다.' }
if ($p8.Name -ne "SubscriptionKey_$keyId.p8") { throw '.env의 키 ID와 .p8 파일 이름이 다릅니다.' }
# 줄바꿈을 \n 두 글자로 바꿔 한 줄로 올린다(서버가 다시 줄바꿈으로 복원한다).
$pem = ((Get-Content -Raw -Encoding UTF8 $p8.FullName).Trim()) -replace "`r?`n", '\n'

# 이 저장소에는 Netlify CLI가 없어 홈페이지 프로젝트의 CLI를 쓴다(로그인·사이트 연결은 .netlify/state.json 기준).
$netlify = 'F:\homepage\kamanbi\node_modules\.bin\netlify.cmd'
if (-not (Test-Path $netlify)) { throw "Netlify CLI를 찾지 못했습니다: $netlify" }
if (-not (Test-Path '.netlify\state.json')) { throw '.netlify\state.json 이 없습니다. 저장소 루트(F:\PDF_daeri)에서 실행하세요.' }

function Set-Var($name, $value) {
  & $netlify env:set $name $value --secret --force | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "$name 등록 실패(netlify login 이 필요할 수 있습니다)." }
  Write-Host "등록됨: $name"
}
Set-Var 'APPLE_IAP_KEY_ID' $keyId
Set-Var 'APPLE_IAP_ISSUER_ID' $issuer
Set-Var 'APPLE_IAP_PRIVATE_KEY' $pem
Write-Host '완료. 서버 함수는 다음 배포부터 이 값을 사용합니다.'
