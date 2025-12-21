@echo off
setlocal enabledelayedexpansion
title Karaoke App - Flexible Setup

echo ==========================================
echo   KARAOKE APP - AUTO SETUP
echo ==========================================

echo [Checking] Dang tim kiem cong cu ADB...

:: Kiem tra xem ADB da co trong he thong chua (Global PATH)
where adb >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Da tim thay ADB trong bien moi truong he thong.
    goto :ADB_DONE
)

::Kiem tra bien moi truong ANDROID_HOME (Neu co)
if defined ANDROID_HOME (
    if exist "%ANDROID_HOME%\platform-tools\adb.exe" (
        echo [OK] Tim thay ADB theo ANDROID_HOME.
        set "PATH=%PATH%;%ANDROID_HOME%\platform-tools"
        goto :ADB_DONE
    )
)

:: Kiem tra thu muc mac dinh (Default Location)
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    echo [OK] Tim thay ADB o thu muc mac dinh.
    set "PATH=%PATH%;%LOCALAPPDATA%\Android\Sdk\platform-tools"
    goto :ADB_DONE
)

::HOI TRUC TIEP NGUOI DUNG
echo.
echo [!] KHONG TIM THAY ADB TU DONG!
echo Co le ban da cai Android SDK o mot thu muc khac.
echo Hay giup toi chi duong dan den thu muc 'platform-tools'.
echo.
set /p USER_ADB_PATH="Paste duong dan thu muc platform-tools tai day: "

:: Xoa dau ngoac kep neu nguoi dung lo copy vao
set "USER_ADB_PATH=!USER_ADB_PATH:"=!"

if exist "!USER_ADB_PATH!\adb.exe" (
    set "PATH=%PATH%;!USER_ADB_PATH!"
    echo [OK] Da cap nhat duong dan ADB.
    goto :ADB_DONE
) else (
    echo [LOI] Duong dan ban nhap khong chua file adb.exe!
    pause
    exit /b
)

:ADB_DONE
adb version >nul 2>&1
if %errorlevel% neq 0 (
    echo [LOI] ADB van khong hoat dong. Vui long kiem tra lai.
    pause
    exit /b
)


::TIM KIEM MAY AO DANG CHAY
echo.
echo [1/2] Dang tim kiem may ao dang hoat dong...

set "RUNNING_ID="
for /f "tokens=2 delims=•" %%a in ('flutter devices ^| findstr "emulator"') do (
    set "RAW_ID=%%a"
    set "RUNNING_ID=!RAW_ID: =!"
    goto :FOUND_ID
)

if not defined RUNNING_ID (
    goto :NO_DEVICE_FOUND
)

:FOUND_ID
echo [OK] Phat hien may ao: !RUNNING_ID!

::CHAY APP
echo.
echo ==========================================
echo   [2/2] BUILD VA CHAY APP TREN: !RUNNING_ID!
echo ==========================================

echo Clean...
call flutter clean >nul 2>&1
echo Pub Get...
call flutter pub get >nul 2>&1

echo Running...
call flutter run -d !RUNNING_ID!

echo.
echo App da tat. Nhan phim bat ky de thoat.
pause
exit /b

:NO_DEVICE_FOUND
echo.
echo ==========================================
echo [LOI] KHONG TIM THAY MAY AO NAO DANG BAT!
echo ==========================================
echo.
echo Vui long mo Android Studio va bat mot may ao len truoc.
echo.
pause
exit /b