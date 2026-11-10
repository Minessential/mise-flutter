@echo off
if "%FIXTURE_BOOTSTRAP_FAIL%"=="1" (
  echo fixture bootstrap failed 1>&2
  exit /b 23
)
echo %* | findstr /C:"--machine" >nul
if errorlevel 1 (
  echo Flutter fixture 9.9.9
  exit /b 0
)
if not exist bin\cache\dart-sdk mkdir bin\cache\dart-sdk
>bin\cache\dart-sdk\version echo 7.7.8
>bin\cache\flutter.version.json echo {"frameworkVersion":"9.9.9","dartSdkVersion":"7.7.8","frameworkRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","channel":"stable"}
>>bootstrap-calls echo bootstrap
type bin\cache\flutter.version.json
