# Apple 앱 내 구입 키를 Netlify 환경 변수로 등록한다(서버 verify-subscription의 iOS 검증용).
# 비밀 값은 이 파일에 없다. F:\keys\PDF_daeri 에서 읽어 Netlify에 올릴 뿐이며,
# Netlify CLI의 출력(오류 포함)은 전부 버려서 어떤 경우에도 값이 화면에 나오지 않는다.
# 실행(PowerShell): 저장소 루트(F:\PDF_daeri)에서
#   powershell -ExecutionPolicy Bypass -File tool\set_netlify_apple_iap_env.ps1
$ErrorActionPreference = 'Stop'
$keys = 'F:\keys\PDF_daeri'
$envText = Get-Content -Raw -Encoding UTF8 (Join-Path $keys '.env')
# 가장 마지막 "app 내 구입" 블록의 issuer ID / 키 ID 를 쓴다(키를 새로 만들면 .env 끝에 갱신해 둔다).
$matches = [regex]::Matches($envText, '(?s)app\s*내\s*구입.*?issuer\s*ID\s*[:：]\s*(\S+).*?키\s*ID\s*[:：]\s*(\S+)', 'IgnoreCase')
if ($matches.Count -eq 0) { throw '.env에서 "app 내 구입" 블록(issuer ID, 키 ID)을 찾지 못했습니다.' }
$m = $matches[$matches.Count - 1]
$issuer = $m.Groups[1].Value
$keyId = $m.Groups[2].Value
$p8 = Join-Path $keys "SubscriptionKey_$keyId.p8"
if (-not (Test-Path $p8)) { throw "SubscriptionKey_$keyId.p8 파일을 F:\keys\PDF_daeri 에서 찾지 못했습니다(.env의 키 ID와 파일 이름이 같아야 합니다)." }
# PEM 전체를 base64 한 줄로 만든다: '-----'로 시작하지 않아 CLI가 옵션으로 오해하지 않는다. 서버가 다시 디코딩한다.
$pemBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($p8))

# 이 저장소에는 Netlify CLI가 없어 홈페이지 프로젝트의 CLI를 쓴다(로그인·사이트 연결은 .netlify\state.json 기준).
$netlify = 'F:\homepage\kamanbi\node_modules\.bin\netlify.cmd'
if (-not (Test-Path $netlify)) { throw "Netlify CLI를 찾지 못했습니다: $netlify" }
if (-not (Test-Path '.netlify\state.json')) { throw '.netlify\state.json 이 없습니다. 저장소 루트(F:\PDF_daeri)에서 실행하세요.' }

function Set-Var($name, $value) {
  # cmd 리다이렉션으로 stdout/stderr 를 모두 버린다(값이 오류 메시지에 섞여 나오는 것을 막는다).
  # 값은 영숫자·-·+·/·= 만 포함하므로 cmd 인용 없이도 안전하다.
  cmd /c "`"$netlify`" env:set $name $value --secret --force --context production >nul 2>&1"
  if ($LASTEXITCODE -ne 0) { throw "$name 등록 실패 (종료 코드 $LASTEXITCODE). netlify login 이 필요할 수 있습니다." }
  Write-Host "등록됨: $name"
}
Set-Var 'APPLE_IAP_KEY_ID' $keyId
Set-Var 'APPLE_IAP_ISSUER_ID' $issuer
Set-Var 'APPLE_IAP_PRIVATE_KEY' $pemBase64
Write-Host '완료. 서버 함수는 다음 배포부터 이 값을 사용합니다.'
