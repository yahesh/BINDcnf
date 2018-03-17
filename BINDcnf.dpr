program BINDcnf;

{$APPTYPE CONSOLE}
{$R DATA.RES}

uses
  WinSvc,
  WinInet,
  Windows,
  SysUtils,
  ShellAPI,
  Registry,
  FileCtrl;

const
  CCacheOff  = '-cache';
  CCacheOn   = '+cache';
  CDNSCache  = 'Dnscache';
  CConfigOff = '-config';
  CConfigOn  = '+config';
  CHelp      = 'help';
  CStart     = 'start';

var
  VNoConfig : Boolean;
  VProceed  : Boolean;

function ConfigureBIND(const AStartService : Boolean) : Boolean; forward;
function DownloadFile(const AURL : String; const AFileName : String) : Boolean; forward;
function ExecuteProgram(const AFileName : String; const AParameters : String) : Boolean; forward;
function GetTimeString : String; forward;
function IsParameterSet(const AParameter : String) : Boolean; forward;
function ServiceGetState(const AServiceName : String) : LongInt; forward;
function ServiceSetBootup(const AServiceName : String; const ABootup : LongWord) : Boolean; forward;
function ServiceStart(const AServiceName : String) : Boolean; forward;
function ServiceStop(const AServiceName : String) : Boolean; forward;
function StripBackslash(const APath : String) : String; forward;

function ConfigureBIND(const AStartService : Boolean) : Boolean;
const
  CBackslash  = '\';
  CBinPath    = 'bin\';
  CConfGen    = 'rndc-confgen.exe';
  CEtcPath    = 'etc\';
  CKeyName    = 'rndc-key';
  CLocalZone  = 'localhost.zone';
  CNamed      = 'named';
  CNamedConf  = 'named.conf';
  CNamedLocal = 'named.local';
  CNamedPid   = 'named.pid';
  CNamedRoot  = 'named.root';
  CPortNum    = '953';
  CRegPath    = '\Software\ISC\BIND\';
  CRegValue   = 'InstallDir';
//  CRndc       = 'rndc.exe';
  CRndcConf   = 'rndc.conf';
  CRndcKey    = 'rndc.key';
  CRootURL    = 'http://internic.net/zones/named.root';
  CServerIP   = '127.0.0.1';
var
  LBindPath  : String;
  LExists    : Boolean;
  LIndex     : LongInt;
  LKeyFile   : array of String;
  LNextLine  : String;
  LReadFile  : TextFile;
  LRegistry  : TRegistry;
  LStartBind : Boolean;
  LStopped   : Boolean;
  LWriteFile : TextFile;
begin
  Result := false;

  LBindPath := '';

  WriteLn('Searching folder ...');
  LRegistry := TRegistry.Create(KEY_READ);
  try
    LRegistry.RootKey := HKEY_LOCAL_MACHINE;

    if LRegistry.OpenKey(CRegPath, false) then
    begin
      try
        LBindPath := LRegistry.ReadString(CRegValue);
        if (LBindPath[Length(LBindPath)] <> CBackslash) then
          LBindPath := LBindPath + CBackslash;
      finally
        LRegistry.CloseKey;
      end;
    end;
  finally
    LRegistry.Free;
  end;

  if DirectoryExists(LBindPath) then
  begin
    WriteLn('Searching bin-folder ...');
    if DirectoryExists(LBindPath + CBinPath) then
    begin
//      WriteLn('Searching rndc.exe ...');
//      if FileExists(LBindPath + CBinPath + CRndc) then
//      begin
        WriteLn('Searching rndc-confgen.exe ...');
        if FileExists(LBindPath + CBinPath + CConfGen) then
        begin
          LStartBind := (ServiceGetState(CNamed) = SERVICE_RUNNING);

          LStopped := not(LStartBind);
          if not(LStopped) then
          begin
            WriteLn('Stopping service ...');
            LStopped := (ServiceSetBootup(CNamed, SERVICE_DEMAND_START) and
                                          ServiceStop(CNamed));
            Sleep(2000); // wait some time
          end;

          if LStopped then
          begin
            LExists := DirectoryExists(LBindPath + CEtcPath);
            if LExists then
            begin
              WriteLn('Renaming etc-folder ...');
              RenameFile(LBindPath + CEtcPath, LBindPath + StripBackslash(CEtcPath) + '_' + GetTimeString + CBackslash);
              LExists := DirectoryExists(LBindPath + CEtcPath);
            end;

            if not(LExists) then
            begin
              WriteLn('Creating etc-folder ...');
              if ForceDirectories(LBindPath + CEtcPath) then
              begin
                WriteLn('Downloading named.root ...');
                if DownloadFile(CRootURL, LBindPath + CEtcPath + CNamedRoot) then
                begin
                  WriteLn('Generating rndc.key ...');
                  ExecuteProgram(LBindPath + CBinPath + CConfGen,
                                 '-a ' +
                                 '-b "512" ' +
                                 '-c "' + LBindPath + CEtcPath + CRndcKey + '" ' +
                                 '-k "' + CKeyName + '" ' +
                                 '-p "' + CPortNum + '" ' +
                                 '-s "' + CServerIP + '"');

                  if FileExists(LBindPath + CEtcPath + CRndcKey) then
                  begin
                    SetLength(LKeyFile, 0);

                    WriteLn('Reading rndc.key ...');
                    AssignFile(LReadFile, LBindPath + CEtcPath + CRndcKey);
                    Reset(LReadFile);
                    try
                      while not(EoF(LReadFile)) do
                      begin
                        ReadLn(LReadFile, LNextLine);

                        SetLength(LKeyFile, Succ(Length(LKeyFile)));
                        LKeyFile[High(LKeyFile)] := LNextLine
                      end;
                    finally
                      CloseFile(LReadFile);
                    end;

                    WriteLn('Deleting rndc.key ...');
                    DeleteFile(LBindPath + CEtcPath + CRndcKey);
                    
                    if not(FileExists(LBindPath + CEtcPath + CRndcKey)) then
                    begin
                      WriteLn('Writing rndc.conf ...');
                      AssignFile(LWriteFile, LBindPath + CEtcPath + CRndcConf);
                      Rewrite(LWriteFile);
                      try
                        for LIndex := 0 to Pred(Length(LKeyFile)) do
                          WriteLn(LWriteFile, LKeyFile[LIndex]);
                        WriteLn(LWriteFile, '');

                        WriteLn(LWriteFile, 'options {');
                        WriteLn(LWriteFile, #$09, 'default-key "', CKeyName, '";');
                        WriteLn(LWriteFile, #$09, 'default-server ', CServerIP, ';');
                        WriteLn(LWriteFile, #$09, 'default-port ', CPortNum, ';');
                        WriteLn(LWriteFile, '};');
                      finally
                        CloseFile(LWriteFile);
                      end;

                      if FileExists(LBindPath + CEtcPath + CRndcConf) then
                      begin
                        WriteLn('Writing named.conf ...');
                        AssignFile(LWriteFile, LBindPath + CEtcPath + CNamedConf);
                        Rewrite(LWriteFile);
                        try
                          WriteLn(LWriteFile, 'options {');
                          WriteLn(LWriteFile, #$09, 'allow-query { ', CServerIP, '; };');
                          WriteLn(LWriteFile, #$09, 'allow-recursion { ', CServerIP, '; };');
                          WriteLn(LWriteFile, #$09, 'directory "', StripBackslash(LBindPath + CEtcPath), '";');
                          WriteLn(LWriteFile, #$09, 'notify no;');
                          WriteLn(LWriteFile, '};');
                          WriteLn(LWriteFile, '');
                          WriteLn(LWriteFile, 'zone "." IN {');
                          WriteLn(LWriteFile, #$09, 'type hint;');
                          WriteLn(LWriteFile, #$09, 'file "', LBindPath, CEtcPath, CNamedRoot, '";');
                          WriteLn(LWriteFile, '};');
                          WriteLn(LWriteFile, '');
                          WriteLn(LWriteFile, 'zone "localhost" IN {');
                          WriteLn(LWriteFile, #$09, 'allow-update { none; };');
                          WriteLn(LWriteFile, #$09, 'file "', LBindPath, CEtcPath, CLocalZone, '";');
                          WriteLn(LWriteFile, #$09, 'type master;');
                          WriteLn(LWriteFile, '};');
                          WriteLn(LWriteFile, '');
                          WriteLn(LWriteFile, 'zone "0.0.127.in-addr.arpa" IN {');
                          WriteLn(LWriteFile, #$09, 'allow-update { none; };');
                          WriteLn(LWriteFile, #$09, 'file "', LBindPath, CEtcPath, CNamedLocal, '";');
                          WriteLn(LWriteFile, #$09, 'type master;');
                          WriteLn(LWriteFile, '};');
                          WriteLn(LWriteFile, '');

                          for LIndex := 0 to Pred(Length(LKeyFile)) do
                            WriteLn(LWriteFile, LKeyFile[LIndex]);
                          WriteLn(LWriteFile, '');

                          WriteLn(LWriteFile, 'controls {');
                          WriteLn(LWriteFile, #$09, 'inet ', CServerIP, ' port ', CPortNum, ' allow { ', CServerIP, '; } keys { "', CKeyName, '"; };');
                          WriteLn(LWriteFile, '};');
                        finally
                          CloseFile(LWriteFile);
                        end;

                        if FileExists(LBindPath + CEtcPath + CNamedConf) then
                        begin
                          WriteLn('Writing localhost.zone ...');
                          AssignFile(LWriteFile, LBindPath + CEtcPath + CLocalZone);
                          Rewrite(LWriteFile);
                          try
                            WriteLn(LWriteFile, '$TTL 3D');
                            WriteLn(LWriteFile, '@', #$09, 'IN', #$09, 'SOA', #$09, 'ns.localhost.', #$09, 'hostmaster.localhost. (');
                            WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '11');
                            WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '8H');
                            WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '2H');
                            WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '4W');
                            WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '1D');
                            WriteLn(LWriteFile, #$09#$09#$09, ')');
                            WriteLn(LWriteFile, '');
                            WriteLn(LWriteFile, #$09, 'IN', #$09, 'NS', #$09, 'ns.localhost.');
                            WriteLn(LWriteFile, '');
                            WriteLn(LWriteFile, 'localhost.', #$09#$09, 'A', #$09, '127.0.0.1');
                            WriteLn(LWriteFile, 'ns.localhost.', #$09#$09, 'A', #$09, '127.0.0.1');
                          finally
                            CloseFile(LWriteFile);
                          end;

                          if FileExists(LBindPath + CEtcPath + CLocalZone) then
                          begin
                            WriteLn('Writing named.local ...');
                            AssignFile(LWriteFile, LBindPath + CEtcPath + CNamedLocal);
                            Rewrite(LWriteFile);
                            try
                              WriteLn(LWriteFile, '$TTL 3D');
                              WriteLn(LWriteFile, '@', #$09, 'IN', #$09, 'SOA', #$09, 'ns.localhost.', #$09, 'hostmaster.localhost. (');
                              WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '11');
                              WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '8H');
                              WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '2H');
                              WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '4W');
                              WriteLn(LWriteFile, #$09#$09#$09#$09#$09, '1D');
                              WriteLn(LWriteFile, #$09#$09#$09, ')');
                              WriteLn(LWriteFile, '');
                              WriteLn(LWriteFile, #$09, 'IN', #$09, 'NS', #$09, 'ns.localhost.');
                              WriteLn(LWriteFile, '');
                              WriteLn(LWriteFile, '1', #$09, 'IN', #$09, 'PTR', #$09, 'localhost.');
                            finally
                              CloseFile(LWriteFile);
                            end;

                            if FileExists(LBindPath + CEtcPath + CNamedLocal) then
                            begin
  //                              WriteLn('Reloading configuration ...');
  //                              ExecuteProgram(LBindPath + CBinPath + CRndc,
  //                                             'reload');

                              Result := not(LStartBind or AStartService);
                              if not(Result) then
                              begin
                                WriteLn('Starting service ...');
                                Result := (ServiceSetBootup(CNamed, SERVICE_AUTO_START) and
                                           ServiceStart(CNamed));
                                Sleep(2000); // wait some time
                                if not(Result) then
                                  WriteLn('Service not started!');
                              end;
                            end
                            else
                              WriteLn('named.local not written!');
                          end
                          else
                            WriteLn('localhost.zone not written!');
                        end
                        else
                          WriteLn('named.conf not written!');
                      end
                      else
                        WriteLn('rndc.conf not written!');
                    end
                    else
                      WriteLn('rndc.key not deleted!');
                  end
                  else
                    WriteLn('rndc.key not generated!');
                end
                else
                  WriteLn('named.root not downloaded!');
              end
              else
                WriteLn('etc-folder not created!');
            end
            else
              WriteLn('etc-folder not renamed!');
          end
          else
            WriteLn('Service not stopped!');
        end
        else
          WriteLn('rndc-confgen.exe not found!');
//      end
//      else
//        WriteLn('rndc.exe not found!');
    end
    else
      WriteLn('bin-folder not found!');
  end
  else
    WriteLn('Folder not found!');
end;

function DownloadFile(const AURL : String; const AFileName : String) : Boolean;
var
  LAborted      : Boolean;
  LBuffer       : array[0..1023] of Char;
  LBytesRead    : LongWord;
  LBytesWritten : LongInt;
  LNetHandle    : HINTERNET;
  LUrlHandle    : HINTERNET;
  LWriteFile    : File of Char;
begin
  Result := false;

  LNetHandle := InternetOpen('BINDcnf', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if (LNetHandle <> nil) then
  begin
    try
      LUrlHandle := InternetOpenUrl(LNetHandle, PChar(AURL), nil, 0, INTERNET_FLAG_RELOAD, 0);
      if (LUrlHandle <> nil) then
      begin
        try
          LAborted := false;

          AssignFile(LWriteFile, AFileName);
          Rewrite(LWriteFile);
          try
            repeat
              InternetReadFile(LUrlHandle, @LBuffer, SizeOf(LBuffer), LBytesRead);

              if (LBytesRead > 0) then
              begin
                BlockWrite(LWriteFile, LBuffer, LBytesRead, LBytesWritten);
                LAborted := (LBytesRead <> LBytesWritten);
              end;
            until ((LBytesRead = 0) or LAborted);
          finally
            CloseFile(LWriteFile);
          end;

          if not(LAborted) then
            Result := FileExists(AFileName);
        finally
          InternetCloseHandle(LUrlHandle);
        end;
      end;
    finally
      InternetCloseHandle(LNetHandle);
    end;
  end;
end;

function ExecuteProgram(const AFileName : String; const AParameters : String) : Boolean;
var
   LExitCode : LongWord;
   LSEInfo   : TShellExecuteInfo;
begin
  Result := false;

  if FileExists(AFileName) then
  begin
    FillChar(LSEInfo, SizeOf(LSEInfo), 0);
    LSEInfo.cbSize       := SizeOf(TShellExecuteInfo);
    LSEInfo.fMask        := SEE_MASK_NOCLOSEPROCESS;
    LSEInfo.lpDirectory  := PChar(ExtractFilePath(AFileName));
    LSEInfo.lpFile       := PChar(AFileName);
    LSEInfo.lpParameters := PChar(AParameters);
    LSEInfo.nShow        := SW_SHOWNORMAL;
    LSEInfo.Wnd          := 0;

    if ShellExecuteEx(@LSEInfo) then
    begin
      repeat
        Sleep(100);

        GetExitCodeProcess(LSEInfo.hProcess, LExitCode);
      until (LExitCode <> STILL_ACTIVE);

      Result := true;
    end;
  end;
end;

function GetTimeString : String;
  function ToString(const ANum : Word; const ALength : Byte) : String;
  begin
    Result := IntToStr(ANum);
    while (Length(Result) < ALength) do
      Result := '0' + Result;
  end;
var
  LDay     : Word;
  LHour    : Word;
  LMinute  : Word;
  LMonth   : Word;
  LMSecond : Word;
  LSecond  : Word;
  LYear    : Word;
begin
  DecodeDate(Now, LYear, LMonth, LDay);
  DecodeTime(Now, LHour, LMinute, LSecond, LMSecond);

  Result := ToString(LYear, 4) + ToString(LMonth, 2) + ToString(LDay, 2) +
            ToString(LHour, 2) + ToString(LMinute, 2) + ToString(LSecond, 2);
end;

function IsParameterSet(const AParameter : String) : Boolean;
var
  LIndex : LongInt;
begin
  Result := false;

  for LIndex := 1 to ParamCount do
  begin
    Result := (AnsiLowerCase(ParamStr(LIndex)) = AnsiLowerCase(AParameter));
    if Result then
      Break;
  end
end;

function ServiceGetState(const AServiceName : String) : LongInt;
var
  LManager : SC_Handle;
  LService : SC_Handle;
  LStatus  : TServiceStatus;
begin
  Result := - 1;

  LManager := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if (LManager <> 0) then
  begin
    try
      LService := OpenService(LManager, PChar(AServiceName), SERVICE_QUERY_STATUS);
      if (LService <> 0) then
      begin
        try
          if QueryServiceStatus(LService, LStatus) then
            Result := LStatus.dwCurrentState;
        finally
          CloseServiceHandle(LService);
        end;
      end;
    finally
      CloseServiceHandle(LManager);
    end;
  end;
end;

function ServiceSetBootup(const AServiceName : String; const ABootup : LongWord) : Boolean;
var
  LBytes   : LongWord;
  LConfig  : PQueryServiceConfig;
  LManager : SC_Handle;
  LService : SC_Handle;
  LSize    : LongWord;
begin
  Result := false;

  LManager := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if (LManager <> 0) then
  begin
    try
      LService := OpenService(LManager, PChar(AServiceName), SERVICE_CHANGE_CONFIG or SERVICE_QUERY_CONFIG);
      if (LService <> 0) then
      begin
        try
          QueryServiceConfig(LService, nil, 0, LBytes);
          LSize := Succ(LBytes);
          
          GetMem(LConfig, LSize);
          try
            if QueryServiceConfig(LService, LConfig, LSize, LBytes) then
            begin
              Result := (LConfig^.dwStartType = ABootup);
              if not(Result) then
                Result := ChangeServiceConfig(LService, SERVICE_NO_CHANGE, ABootup, SERVICE_NO_CHANGE,
                                              nil, nil, nil, nil, nil, nil, nil);
            end;
          finally
            FreeMem(LConfig, LSize);
          end;
        finally
          CloseServiceHandle(LService);
        end;
      end;
    finally
      CloseServiceHandle(LManager);
    end;
  end;
end;

function ServiceStart(const AServiceName : String) : Boolean;
var
  LCheckPoint : LongWord;
  LExit       : Boolean;
  LManager    : SC_Handle;
  LService    : SC_Handle;
  LStatus     : TServiceStatus;
  LTemp       : PChar;
begin
  Result := false;

  if not(Result) then
  begin
    LManager := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
    if (LManager <> 0) then
    begin
      try
        LService := OpenService(LManager, PChar(AServiceName), SERVICE_START or SERVICE_QUERY_STATUS);
        if (LService <> 0) then
        begin
          try
            if QueryServiceStatus(LService, LStatus) then
            begin
              Result := (LStatus.dwCurrentState = SERVICE_RUNNING);
              if not(Result) then
              begin
                LTemp := nil;
                if StartService(LService, 0, LTemp) then
                begin
                  repeat
                    LCheckPoint := LStatus.dwCheckPoint;
                    Sleep(LStatus.dwWaitHint);

                    LExit := not(QueryServiceStatus(LService, LStatus));
                    if not(LExit) then
                      LExit := (LStatus.dwCheckPoint < LCheckPoint);
                  until ((LStatus.dwCurrentState = SERVICE_RUNNING) or LExit);

                  Result := (LStatus.dwCurrentState = SERVICE_RUNNING);
                end;
              end;
            end;
          finally
            CloseServiceHandle(LService);
          end;
        end;
      finally
        CloseServiceHandle(LManager);
      end;
    end;
  end;
end;

function ServiceStop(const AServiceName : String) : Boolean;
var
  LCheckPoint : LongWord;
  LExit       : Boolean;
  LManager    : SC_Handle;
  LService    : SC_Handle;
  LStatus     : TServiceStatus;
begin
  Result := false;

  if not(Result) then
  begin
    LManager := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
    if (LManager <> 0) then
    begin
      try
        LService := OpenService(LManager, PChar(AServiceName), SERVICE_STOP or SERVICE_QUERY_STATUS);
        if (LService <> 0) then
        begin
          try
            if QueryServiceStatus(LService, LStatus) then
            begin
              Result := (LStatus.dwCurrentState = SERVICE_STOPPED);
              if not(Result) then
              begin
                if ControlService(LService, SERVICE_CONTROL_STOP, LStatus) then
                begin
                  repeat
                    LCheckPoint := LStatus.dwCheckPoint;
                    Sleep(LStatus.dwWaitHint);

                    LExit := not(QueryServiceStatus(LService, LStatus));
                    if not(LExit) then
                      LExit := (LStatus.dwCheckPoint < LCheckPoint);
                  until ((LStatus.dwCurrentState = SERVICE_STOPPED) or LExit);

                  Result := (LStatus.dwCurrentState = SERVICE_STOPPED);
                end;
              end;
            end;
          finally
            CloseServiceHandle(LService);
          end;
        end;
      finally
        CloseServiceHandle(LManager);
      end;
    end;
  end;
end;

function StripBackslash(const APath : String) : String;
const
  CBackslash = '\';
begin
  Result := APath;
  if (Result[Length(Result)] = CBackSlash) then
    Delete(Result, Length(Result), 1);
end;

begin
  WriteLn('');
  WriteLn('BINDcnf 0.3b1');
  WriteLn('(C) 2009-2018 hello@yahe.sh');
  WriteLn('');

  if IsParameterSet(CHelp) then
  begin
    WriteLn(ExtractFileName(ParamStr(0)), ' [', CCacheOff, '|', CCacheOn, '] [',
            CConfigOff, '|', CConfigOn, '] [', CHelp, '] [', CStart, ']');
    WriteLn('');
    WriteLn(CCacheOff, '    deactivate Windows DNS cache');
    WriteLn(CCacheOn, '    activate Windows DNS cache');
    WriteLn(CConfigOff, '   skip configuration');
    WriteLn(CConfigOn, '   force configuration (on cache error)');
    WriteLn(CHelp, '      show this help');
    WriteLn(CStart, '     start BIND service');
  end
  else
  begin
    VNoConfig := false;
    VProceed  := true;

    if IsParameterSet(CCacheOff) then
    begin
      WriteLn('Deactivating DNS cache ...');
      VProceed := (ServiceSetBootup(CDNSCache, SERVICE_DEMAND_START) and
                   ServiceStop(CDNSCache));
      if not(VProceed) then
        WriteLn('DNS cache not deactivated!');
      WriteLn('');
    end
    else
    begin
      if IsParameterSet(CCacheOn) then
      begin
        WriteLn('Activating DNS cache ...');
        VProceed := (ServiceSetBootup(CDNSCache, SERVICE_AUTO_START) and
                     ServiceStart(CDNSCache));
        if not(VProceed) then
          WriteLn('DNS cache not activated!');
        WriteLn('');
      end;
    end;

    if not(VProceed) then
      VProceed := IsParameterSet(CConfigOn);
    if VProceed then
    begin
      VProceed  := not(IsParameterSet(CConfigOff));
      VNoConfig := not(VProceed);
    end;

    if VProceed then
    begin
      if ConfigureBIND(IsParameterSet(CStart)) then
      begin
        WriteLn('');
        WriteLn('CONFIGURATION SUCCEEDED');
      end
      else
      begin
        WriteLn('');
        WriteLn('CONFIGURATION FAILED');
      end;
    end
    else
    begin
      if VNoConfig then
        WriteLn('CONFIGURATION SKIPPED')
      else
        WriteLn('EXECUTION FAILED');
    end;
  end;

  WriteLn('');
end.
