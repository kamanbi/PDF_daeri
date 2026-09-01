[Setup]
AppName=PDF 대리
AppVersion=1.1.5
AppPublisher=com.kamanbi
DefaultDirName={autopf}\PDF 대리
DefaultGroupName=PDF 대리
OutputDir=F:\PDF_daeri\build\windows\x64\installer
OutputBaseFilename=PDF대리Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.19041
UninstallDisplayIcon={app}\pdf_daeri.exe

[Files]
Source: "F:\PDF_daeri\build\windows\x64\runner\Release\pdf_daeri.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "F:\PDF_daeri\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "F:\PDF_daeri\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "F:\PDF_daeri\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "F:\PDF_daeri\windows\installer\vcredist_x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\PDF 대리"; Filename: "{app}\pdf_daeri.exe"
Name: "{group}\{cm:UninstallProgram,PDF 대리}"; Filename: "{uninstallexe}"

[Run]
Filename: "{tmp}\vcredist_x64.exe"; StatusMsg: "Visual C++ 재배포 패키지 설치 중..."; Parameters: "/install /quiet /norestart"
