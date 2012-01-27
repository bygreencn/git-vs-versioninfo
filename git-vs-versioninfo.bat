@ECHO OFF
SETLOCAL

REM  Script for generation of rc VERSIONINFO & StringFileInfo

REM ====================
REM Installation Variables
REM ====================
:: VERSION_FILE - Untracked file to be included in packaged source releases.
::                it should contain a single line in the format:
::                $Project_Name VERSION $tag (ie: Foobar VERSION v1.0.0-alpha0)
SET VERSION_FILE=.git-vs-versioninfo

:: DEFAULT_VERSION - Version string to be processed when neither Git nor a
::                packed version file is available.
SET DEFAULT_VERSION=v1.0.0-devel

:: COUNT_PATCHES_FROM - Determines which tag to count the number of patches from
::                for the final portion (build) of the technical version number.
::                This version number is very usefull as Assembly Version.
::                Valid values are:
::                   major - count from earliest Major.0.0* tag.
::                   minor - count from earliest Major.Minor.0* tag.
::                   maint - count from earliest Major.Minor.Maint tag.
SET COUNT_PATCHES_FROM=maint

:: --------------------
:CHECK_ARGS
:: --------------------

:: Console output only.
IF [%1] == [] GOTO START

IF "%~1" == "--help" GOTO USAGE
IF "%~1" == "--quiet" SET fQUIET=1& SHIFT
IF "%~1" == "--force" SET fFORCE=1& SHIFT

IF EXIST %~1\NUL (
  :: %1 is a path
  SET CACHE_FILE=%~s1\%VERSION_FILE%
  SHIFT
)

IF [%~nx1] NEQ [] (
  :: %1 is a file
  SET HEADER_OUT_FILE=%~fs1
  SHIFT
)
:: This should always be the last argument.
IF [%1] NEQ [] GOTO USAGE

:: Some basic sanity checks.
IF DEFINED fQUIET (
  IF NOT DEFINED HEADER_OUT_FILE GOTO USAGE
)

IF DEFINED CACHE_FILE (
  SET CACHE_FILE=%CACHE_FILE:\\=\%
  IF NOT DEFINED HEADER_OUT_FILE GOTO USAGE
)
GOTO START

:: --------------------
:USAGE
:: --------------------
ECHO usage: [--help] ^| ^| [--quiet] [--force] [CACHE PATH] [OUT FILE]
ECHO.
ECHO  When called without arguments version information writes to console.
ECHO.
ECHO  --help      - displays this output.
ECHO.
ECHO  --quiet     - Suppress console output.
ECHO  --force     - Ignore cached version information.
ECHO  CACHE PATH  - Path for non-tracked file to store git-describe version.
ECHO  OUT FILE    - Path to writable file that is included in the project's rc file.
ECHO.
ECHO.Version information is expected to be in the format: vMajor[.Minor[.Maint[.Bugfix]]][-stage#][-Patchcount-Committish]
ECHO.Where -stage# is alpha, beta, or rc. ( example: v1.0.0-alpha0 )
ECHO.
ECHO.Example pre-build event:
ECHO.CALL $(SolutionDir)scripts\git-vs-versioninfo.bat "$(SolutionDir)scripts\" "$(ProjectDir)git-vs-versioninfo.cs"
ECHO.
GOTO END

REM ===================
REM Entry Point
REM ===================
:START
ECHO.
CALL :INIT_VARS
CALL :GET_VERSION_STRING
IF DEFINED fGIT_AVAILABLE (
  IF DEFINED fLEAVE_NOW GOTO END
  IF DEFINED CACHE_FILE (
    CALL :CHECK_CACHE
  )
)
CALL :GET_VS_DETAILS
CALL :WRITE_CACHE
IF DEFINED fLEAVE_NOW GOTO END
CALL :PARSE_FULL_VERSION
CALL :SET_DETAILS
CALL :SET_VERSION_DIGITS
CALL :PREP_OUT
IF DEFINED HEADER_OUT_FILE (
  CALL :WRITE_OUT
)
GOTO END

REM ====================
REM FUNCTIONS
REM ====================
:: --------------------
:INIT_VARS
SET FULL_VERSION=
SET PLUGIN_API_VERSION=0
for %%A in (.) do SET SW_NAME=%%~nA

SET vPATCH_PATCHES=
SET vMAINT_PATCHES=
SET vMINOR_PATCHES=
SET vMAJOR_PATCHES=

:: Flags
SET fPRIVATE=0
SET fPATCHED=0
SET fPRE_RELEASE=0

:: Version Descriptions
SET vTYPE=
SET vBUILD=
GOTO :EOF

:: --------------------
:GET_VERSION_STRING
:: --------------------
:: Precedence is Git, VERSION_FILE, then DEFAULT_VERSION.
:: Check if git is available by testing git describe.
IF NOT DEFINED fQUIET (
  ECHO GIT VisualStudio Version
  ECHO ========================
  ECHO.
)
CALL git describe --match v* HEAD > NUL 2>&1
IF NOT ERRORLEVEL 1 (
  SET fGIT_AVAILABLE=1
  :: Parse git version string
  CALL :GET_FULL_VERSION
) ELSE (
  :: Use the VERSION_FILE if it exists.
  IF EXIST "%VERSION_FILE%" (
    FOR /F "tokens=1,2,3" %%A IN (%VERSION_FILE%) DO (
      IF "%%B" EQU "VERSION" (
		SET FULL_VERSION=v%%C
		SET SW_NAME=%%A
	  ) ELSE (
		SET FULL_VERSION=%DEFAULT_VERSION%
	  )
    )
	SET SW_NAME=%SW_NAME:_= %
  ) ELSE (
    :: Default to the DEFAULT_VERSION
    SET FULL_VERSION=%DEFAULT_VERSION%
  )
)
SET FULL_VERSION=%FULL_VERSION:~1%
GOTO :EOF

:: --------------------
:GET_FULL_VERSION
:: --------------------
FOR /F "tokens=*" %%A IN ('"git describe --long --dirty --match v* 2> NUL"') DO (
  SET FULL_VERSION=%%A
)
FOR /F "tokens=2 delims=v" %%A IN ('"git describe --abbrev=0 --match plugin-api-v* 2> NUL"') DO (
  SET PLUGIN_API_VERSION=%%A
)

FOR /F "tokens=*" %%A IN ('"git rev-parse --show-toplevel 2> NUL"') DO SET GIT_ROOT=%%A
for %%A in (%GIT_ROOT%) do SET SW_NAME=%%~nA

SET tmp=
CALL git update-index -q --refresh >NUL 2>&1
IF ERRORLEVEL 1 (
  IF [%fFORCE%] EQU [1] (
    verify > nul
  ) ELSE (
    ECHO >> The working tree index is not prepared for build testing!
    ECHO >> Please check git status or use --force to ignore the index state.
    SET fLEAVE_NOW=1
  )
)
SET tmp=
GOTO :EOF

:: --------------------
:CHECK_CACHE
:: --------------------
:: Exit early if a cached git built version matches the current version.
IF DEFINED HEADER_OUT_FILE (
  IF EXIST "%HEADER_OUT_FILE%" (
    IF [%fFORCE%] EQU [1] DEL "%CACHE_FILE%"
    IF EXIST "%CACHE_FILE%" (
      FOR /F "tokens=1,2,3" %%A IN (%CACHE_FILE%) DO (
        IF "%%C" == "%FULL_VERSION%" (
          IF NOT DEFINED fQUIET (
            ECHO Build version is assumed unchanged from: %FULL_VERSION%.
          )
          SET fLEAVE_NOW=1
        )
      )
    )
  )
)
GOTO :EOF

:: --------------------
:GET_VS_DETAILS
:: --------------------
IF "%SolutionName%" NEQ "" SET SW_NAME=%SolutionName%
GOTO :EOF

:: --------------------
:WRITE_CACHE
:: --------------------
ECHO %SW_NAME: =_% VERSION %FULL_VERSION%> "%CACHE_FILE%"
GOTO :EOF

:: --------------------
:PARSE_FULL_VERSION
:: --------------------
IF NOT DEFINED fQUIET (
  ECHO NAME: %SW_NAME%
  ECHO.
  ECHO VERSION PARSING
  ECHO ---------------
  ECHO FULL VERSION:		%FULL_VERSION%
)
FOR /F "tokens=1,2,* delims=-" %%A IN ("%FULL_VERSION%") DO (
  SET VERSION=%%A
  SET SCND_PART=%%B
  SET /A SCND_NUMBER=%%B
  SET VERSION_REST=%%C
)
IF [%SCND_PART%] EQU [%SCND_NUMBER%] (
  REM Patch Count; no stage identifier
  SET STAGE=
  SET PATCHCOUNT=%SCND_PART%
) ELSE (
  REM Not Patch Count, thus stage identifier
  SET STAGE=%SCND_PART%
  FOR /F "tokens=1,* delims=-" %%A IN ("%VERSION_REST%") DO (
    SET PATCHCOUNT=%%A
    SET VERSION_REST=%%B
  )
)
FOR /F "tokens=1,2,* delims=-" %%A IN ("%VERSION_REST%") DO (
  SET COMMITTISH=%%A
  SET MARKER=%%B
  SET VERSION_REST=%%C
)
IF [%MARKER%] EQU [] SET MARKER=clean
IF NOT DEFINED fQUIET (
  ECHO Version:		%VERSION%
  ECHO Stage identifier:	%STAGE%
  ECHO Patch count:		%PATCHCOUNT%
  ECHO Committish:		%COMMITTISH%
  ECHO Dirty marker:		%MARKER%
  ECHO Rest:				%VERSION_REST%
  ECHO.
)
GOTO :EOF

:: --------------------
:SET_DETAILS
:: --------------------
IF NOT DEFINED fQUIET (
  ECHO VERSION TYPE
  ECHO ------------
)
SET STAGENO=
SET STAGE=-%STAGE%
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,6%" EQU "-devel" (
  SET STAGENO=%STAGE:~6%
  SET vTYPE=Development Release
))
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,6%" EQU "-alpha" (
  SET STAGENO=%STAGE:~6%
  SET vTYPE=Alpha Release
))
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,5%" EQU "-beta" (
  SET STAGENO=%STAGE:~5%
  SET vTYPE=Beta Release
))
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,3%" EQU "-rc" (
  SET STAGENO=%STAGE:~3%
  SET vTYPE=Release Candidate
))
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,3%" EQU "-gm" (
  SET STAGENO=%STAGE:~3%
  SET vTYPE=Version Release
))
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,4%" EQU "-dev" (
  SET STAGENO=%STAGE:~4%
  SET vTYPE=Development Release
))
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,2%" EQU "-a" (
  SET STAGENO=%STAGE:~2%
  SET vTYPE=Alpha Release
))
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,2%" EQU "-b" (
  SET STAGENO=%STAGE:~2%
  SET vTYPE=Beta Release
))
IF "%vTYPE%" EQU "" ( IF "%STAGE:~,2%" EQU "-r" (
  SET STAGENO=%STAGE:~2%
  SET vTYPE=Release Candidate
))
SET STAGE=%STAGE:~1%
IF "%vTYPE%" EQU "" (
  IF [%STAGE%] EQU [] (
	SET vTYPE=Version Release
  ) ELSE (
	SET vTYPE=Version Release [%STAGE%]
  )
) ELSE (
  IF "%vTYPE%" NEQ "Version Release" (
  IF "%STAGENO%" NEQ "" SET vTYPE=%vTYPE% %STAGENO%
	SET fPRE_RELEASE=1
  )
)
IF NOT DEFINED fQUIET (
  ECHO Release type:		%vTYPE%
)
IF "%MARKER%" EQU "dirty" (
	SET vBUILD=Private Build
	SET fPATCHED=1
	SET fPRIVATE=1
) ELSE (
  IF "%PATCHCOUNT%" NEQ "0" (
		SET vBUILD=Patch Build
		SET fPATCHED=1
	) ELSE (
		SET vBUILD=Release Build
	)
)
IF NOT DEFINED fQUIET (
  ECHO Build type:		%vBUILD%
  ECHO.
  ECHO [F] Patched:		%fPATCHED%
  ECHO [F] Private:		%fPRIVATE%
  ECHO [F] PreRelease:		%fPRE_RELEASE%
  ECHO.
)
GOTO :EOF


:: --------------------
:SET_VERSION_DIGITS
:: --------------------
IF NOT DEFINED fQUIET (
  ECHO VERSION DIGITS
  ECHO --------------
)
FOR /F "tokens=1,2,3,4* delims=." %%A IN ("%VERSION%") DO (
  SET vMAJOR=%%A
  SET vMINOR=%%B
  SET vMAINT=%%C
  SET vPATCH=%%D
  SET vLOST=%%E
)
IF [%vMAJOR%] EQU [] SET vMAJOR=0
IF [%vMINOR%] EQU [] SET vMINOR=0
IF [%vMAINT%] EQU [] SET vMAINT=0
IF [%vPATCH%] EQU [] SET vPATCH=0
IF DEFINED fGIT_AVAILABLE (
	CALL :GET_PATCHCOUNTS
)
IF [%vMAJOR_PATCHES%] EQU [] SET vMAJOR_PATCHES=0
IF [%vMINOR_PATCHES%] EQU [] SET vMINOR_PATCHES=0
IF [%vMAINT_PATCHES%] EQU [] SET vMAINT_PATCHES=0
IF [%vPATCH_PATCHES%] EQU [] SET vPATCH_PATCHES=0
SET VERSION_PRODUCT=%vMAJOR%.%vMINOR%.%vMAINT%.%vPATCH%
SET VERSION_TECHNICAL=%vMAJOR%.%vMINOR%.%vMAINT%.%vMAINT_PATCHES%
IF [%COUNT_PATCHES_FROM%] EQU [minor] SET VERSION_TECHNICAL=%vMAJOR%.%vMINOR%.%vMAINT%.%vMINOR_PATCHES%
IF [%COUNT_PATCHES_FROM%] EQU [major] SET VERSION_TECHNICAL=%vMAJOR%.%vMINOR%.%vMAINT%.%vMAJOR_PATCHES%
IF NOT DEFINED fQUIET (
  ECHO Major:			%vMAJOR%	[%vMAJOR_PATCHES%]
  ECHO Minor:			%vMINOR%	[%vMINOR_PATCHES%]
  ECHO Maintenance:		%vMAINT%	[%vMAINT_PATCHES%]
  ECHO Bugfix:			%vPATCH%	[%vPATCH_PATCHES%]
  ECHO [Removed]:		%vLOST%
  ECHO.
  ECHO Product version:	%VERSION_PRODUCT%
  ECHO Technical version:	%VERSION_TECHNICAL%
  ECHO Plugin API version:	%PLUGIN_API_VERSION%
  ECHO.
)
GOTO :EOF

:: --------------------
:GET_PATCHCOUNTS
:: --------------------
SET vPATCH_ID=
SET vMAINT_ID=
SET vMINOR_ID=
SET vMAJOR_ID=
FOR /F "tokens=*" %%A IN ('"git describe --long --match v%vMAJOR%.%vMINOR%.%vMAINT%.%vPATCH% 2> NUL"') DO (
  SET vPATCH_ID=%%A
)
IF [%vPATCH_ID%] EQU [] SET vPATCH_ID=v0-0
FOR /F "tokens=*" %%A IN ('"git describe --long --match v%vMAJOR%.%vMINOR%.%vMAINT%.0 2> NUL"') DO (
  SET vMAINT_ID=%%A
)
IF [%vMAINT_ID%] EQU [] (
  FOR /F "tokens=*" %%A IN ('"git describe --long --match v%vMAJOR%.%vMINOR%.%vMAINT% 2> NUL"') DO (
    SET vMAINT_ID=%%A
  )
)
IF [%vMAINT_ID%] EQU [] SET vMAINT_ID=%vPATCH_ID%
FOR /F "tokens=*" %%A IN ('"git describe --long --match v%vMAJOR%.%vMINOR%.0 2> NUL"') DO (
  SET vMINOR_ID=%%A
)
IF [%vMINOR_ID%] EQU [] (
  FOR /F "tokens=*" %%A IN ('"git describe --long --match v%vMAJOR%.%vMINOR% 2> NUL"') DO (
    SET vMINOR_ID=%%A
  )
)
IF [%vMINOR_ID%] EQU [] SET vMINOR_ID=%vMAINT_ID%
FOR /F "tokens=*" %%A IN ('"git describe --long --match v%vMAJOR%.0 2> NUL"') DO (
  SET vMAJOR_ID=%%A
)
IF [%vMAJOR_ID%] EQU [] (
  FOR /F "tokens=*" %%A IN ('"git describe --long --match v%vMAJOR% 2> NUL"') DO (
    SET vMAJOR_ID=%%A
  )
)
IF [%vMAJOR_ID%] EQU [] SET vMAJOR_ID=%vMINOR_ID%
FOR /F "tokens=2 delims=-" %%A IN ("%vPATCH_ID%") DO SET vPATCH_PATCHES=%%A
FOR /F "tokens=2 delims=-" %%A IN ("%vMAINT_ID%") DO SET vMAINT_PATCHES=%%A
FOR /F "tokens=2 delims=-" %%A IN ("%vMINOR_ID%") DO SET vMINOR_PATCHES=%%A
FOR /F "tokens=2 delims=-" %%A IN ("%vMAJOR_ID%") DO SET vMAJOR_PATCHES=%%A
GOTO :EOF

:: --------------------
:PREP_OUT
:: --------------------
IF NOT %fPRIVATE% EQU 0 ( SET fPRIVATE=true) ELSE ( SET fPRIVATE=false)
IF NOT %fPATCHED% EQU 0 ( SET fPATCHED=true) ELSE ( SET fPATCHED=false)
IF NOT %fPRE_RELEASE% EQU 0 ( SET fPRE_RELEASE=true) ELSE ( SET fPRE_RELEASE=false)
GOTO :EOF

:: --------------------
:WRITE_OUT
:: --------------------
SET SCRIPT_NAME=%~n0%
ECHO.// Generated version info [%SCRIPT_NAME%].>"%HEADER_OUT_FILE%"
ECHO.using System; >> "%HEADER_OUT_FILE%"
REM ECHO. >> "%HEADER_OUT_FILE%"
ECHO.namespace BuildInfo >> "%HEADER_OUT_FILE%"
ECHO.{ >> "%HEADER_OUT_FILE%"
ECHO.    // %SW_NAME% v%VERSION% - %vTYPE% >> "%HEADER_OUT_FILE%"
ECHO.    // Build: %FULL_VERSION% (%vBUILD%) >> "%HEADER_OUT_FILE%"
ECHO.    public static class Version >> "%HEADER_OUT_FILE%"
ECHO.    { >> "%HEADER_OUT_FILE%"
ECHO.        public const string		Version				= "%VERSION%";				>> "%HEADER_OUT_FILE%"
ECHO.        public const string		Build				= "%FULL_VERSION%";			>> "%HEADER_OUT_FILE%"
ECHO.        public const int		PatchCount			= %PATCHCOUNT%;					>> "%HEADER_OUT_FILE%"
ECHO.        public const string		Committish			= "%COMMITTISH%";			>> "%HEADER_OUT_FILE%"
ECHO.        public const string		ReleaseType			= "%vTYPE%";				>> "%HEADER_OUT_FILE%"
ECHO.        public const string		BuildType			= "%vBUILD%";				>> "%HEADER_OUT_FILE%"
ECHO.        public const bool		IsPatched			= %fPATCHED%;					>> "%HEADER_OUT_FILE%"
ECHO.        public const bool		IsPrivate			= %fPRIVATE%;					>> "%HEADER_OUT_FILE%"
ECHO.        public const bool		IsPreRelease		= %fPRE_RELEASE%;			>> "%HEADER_OUT_FILE%"
ECHO.        public const int		Major				= %vMAJOR%;						>> "%HEADER_OUT_FILE%"
ECHO.        public const int		Minor				= %vMINOR%;						>> "%HEADER_OUT_FILE%"
ECHO.        public const int		Maintenaince		= %vMAINT%;					>> "%HEADER_OUT_FILE%"
ECHO.        public const int		Bugfix				= %vPATCH%;						>> "%HEADER_OUT_FILE%"
ECHO.        public const int		PatchesMajor		= %vMAJOR_PATCHES%;			>> "%HEADER_OUT_FILE%"
ECHO.        public const int		PatchesMinor		= %vMINOR_PATCHES%;			>> "%HEADER_OUT_FILE%"
ECHO.        public const int		PatchesMaintenaince	= %vMAINT_PATCHES%;			>> "%HEADER_OUT_FILE%"
ECHO.        public const int		PatchesBugfix		= %vPATCH_PATCHES%;			>> "%HEADER_OUT_FILE%"
ECHO.        public const string		ProductVersion		= "%VERSION_PRODUCT%";	>> "%HEADER_OUT_FILE%"
ECHO.        public const string		TechnicalVersion	= "%VERSION_TECHNICAL%";>> "%HEADER_OUT_FILE%"
ECHO.    } >> "%HEADER_OUT_FILE%"
ECHO. >> "%HEADER_OUT_FILE%"
ECHO.    public static class PluginApi >> "%HEADER_OUT_FILE%"
ECHO.    { >> "%HEADER_OUT_FILE%"
ECHO.        public const int		Version	= %PLUGIN_API_VERSION%; >> "%HEADER_OUT_FILE%"
ECHO.    } >> "%HEADER_OUT_FILE%"
ECHO.} >> "%HEADER_OUT_FILE%"
GOTO :EOF

:: --------------------
:END
:: --------------------