#define AppName "TesterLoop Admin"
#define AppVersion "0.17.1"
#define AppPublisher "TesterLoop"
#define AppExe "TesterLoopAdmin.exe"

#ifndef Arch
#define Arch "x64"
#endif

#if Arch == "x86"
#define SourceDir "..\build\admin-win-x86"
#else
#define SourceDir "..\build\admin-win-x64"
#endif

[Setup]
AppId={{A8C0E1D4-5B3F-4C88-9B75-7E2D4A91C6F2}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\build\admin-win-{#Arch}
OutputBaseFilename=TesterLoop-Admin-Setup-{#Arch}
SetupIconFile=..\media\icons\testerloop.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
#if Arch == "x86"
ArchitecturesAllowed=x86compatible
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "TesterLoop-Admin-Setup-*.exe"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent


