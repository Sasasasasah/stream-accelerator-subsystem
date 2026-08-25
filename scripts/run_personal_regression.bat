@echo off
setlocal EnableExtensions
pushd "%~dp0.."

call scripts\run_srf_mem_sxm_regression.bat
if errorlevel 1 goto fail

call scripts\run_mem_srf_sxm_loopback_e2e.bat
if errorlevel 1 goto fail

echo ========================================
echo STREAM_ACCELERATOR_SUBSYSTEM TEST_PASS
echo ========================================
popd
exit /b 0

:fail
echo STREAM_ACCELERATOR_SUBSYSTEM TEST_FAIL
popd
exit /b 1
