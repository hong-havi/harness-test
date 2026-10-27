@echo off
REM relay-start.bat — Task Scheduler 가 호출할 wrapper.
REM bash.exe 경로를 어디서 찾을지 고정 (설치 위치 다르면 수정).

set BASH_EXE=C:\Program Files\Git\bin\bash.exe
set REPO=D:\workspace_hong\harness-test

if not exist "%BASH_EXE%" (
  echo ERROR: git-bash not found at %BASH_EXE% 1>&2
  exit /b 1
)

"%BASH_EXE%" -lc "cd '%REPO%' && ./scripts/slack/relay.sh __daemon >> .harness/coord/relay.log 2>&1"
