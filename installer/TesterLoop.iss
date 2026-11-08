#define AppName "TesterLoop"
#define AppVersion "0.16.0"
#define AppPublisher "TesterLoop"
#define AppExe "TesterLoop.exe"

#ifndef Arch
#define Arch "x64"
#endif

#if Arch == "x86"
#define SourceDir "..\build\win-x86"
#else
#define SourceDir "..\build\win-x64"
#endif

[Setup]
AppId={{6B1E4F2A-9C3D-4E7B-8A51-2F0D6C9B4A11}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\build\win-{#Arch}
OutputBaseFilename=TesterLoop-Setup-{#Arch}
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
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "TesterLoop-Setup-*.exe"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
