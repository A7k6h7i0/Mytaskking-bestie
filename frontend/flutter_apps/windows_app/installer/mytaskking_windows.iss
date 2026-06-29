[Setup]
AppId={{D8C381D0-142A-4A70-80FD-9BFF99A55111}
AppName=MyTaskKing
AppVersion=1.0.0
AppPublisher=MyTaskKing
AppPublisherURL=https://mytaskking.com
AppSupportURL=https://mytaskking.com
AppUpdatesURL=https://mytaskking.com
DefaultDirName={autopf64}\MyTaskKing
DefaultGroupName=MyTaskKing
AllowNoIcons=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=mytaskking_windows_setup_1.0.0
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UninstallDisplayIcon={app}\mytaskking_windows.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardSmallImageFile=assets\wizard_small.bmp
WizardImageFile=assets\wizard_large.bmp

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MyTaskKing"; Filename: "{app}\mytaskking_windows.exe"
Name: "{group}\Uninstall MyTaskKing"; Filename: "{uninstallexe}"
Name: "{autodesktop}\MyTaskKing"; Filename: "{app}\mytaskking_windows.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\mytaskking_windows.exe"; Description: "Launch MyTaskKing"; Flags: nowait postinstall skipifsilent
