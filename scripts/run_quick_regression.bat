@echo off
setlocal EnableExtensions
pushd "%~dp0.."

set "OUTDIR=sim\quick_regression"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo ========================================
echo STREAM ACCELERATOR QUICK REGRESSION
echo ========================================

echo RUN_STAGE SRF_BASIC_RUNTIME
iverilog -g2012 -Wall -s tb_sr_basic_pipeline -o "%OUTDIR%\tb_sr_basic_pipeline.vvp" ^
  rtl\srf\core\stream_sr_superlane_col_dir.v ^
  rtl\srf\core\stream_sr_column_dir.v ^
  rtl\srf\core\stream_sr_direction_fabric.v ^
  rtl\srf\core\stream_sr_hemisphere_fabric.v ^
  rtl\srf\core\stream_sr_fabric.v ^
  tb\standalone\tb_sr_basic_pipeline.v > "%OUTDIR%\srf_basic_compile.log" 2>&1
if errorlevel 1 goto fail
vvp "%OUTDIR%\tb_sr_basic_pipeline.vvp" > "%OUTDIR%\srf_basic_runtime.log" 2>&1
if errorlevel 1 goto fail
findstr /C:"TEST_FAIL" "%OUTDIR%\srf_basic_runtime.log" >nul
if not errorlevel 1 goto fail
findstr /X /C:"TEST_PASS" "%OUTDIR%\srf_basic_runtime.log" >nul
if errorlevel 1 goto fail
echo SRF BASIC                 PASS

echo RUN_STAGE SRF_SXM_INTEGRATION_RUNTIME
iverilog -g2012 -Wall -s tb_srf_sxm_integration -o "%OUTDIR%\tb_srf_sxm_integration.vvp" ^
  rtl\srf\core\stream_sr_superlane_col_dir.v ^
  rtl\srf\core\stream_sr_column_dir.v ^
  rtl\srf\core\stream_sr_direction_fabric.v ^
  rtl\srf\core\stream_sr_hemisphere_fabric.v ^
  rtl\srf\core\stream_sr_fabric.v ^
  rtl\sxm\sxm_command_decode.v ^
  rtl\sxm\sxm_transpose_superlane_leaf.v ^
  rtl\sxm\sxm_transpose_control_column.v ^
  rtl\sxm\sxm_transpose_result_buffer_array.v ^
  rtl\sxm\sxm_permute_engine.v ^
  rtl\sxm\sxm_slice.v ^
  rtl\sxm\sxm_full.v ^
  rtl\integration\srf_sxm_adapter.v ^
  rtl\integration\srf_sxm_integration_top.v ^
  tb\integration\tb_srf_sxm_integration.v > "%OUTDIR%\srf_sxm_compile.log" 2>&1
if errorlevel 1 goto fail
vvp "%OUTDIR%\tb_srf_sxm_integration.vvp" > "%OUTDIR%\srf_sxm_runtime.log" 2>&1
if errorlevel 1 goto fail
findstr /C:"TEST_FAIL" "%OUTDIR%\srf_sxm_runtime.log" >nul
if not errorlevel 1 goto fail
findstr /X /C:"SRF_SXM_INTEGRATION TEST_PASS" "%OUTDIR%\srf_sxm_runtime.log" >nul
if errorlevel 1 goto fail
echo SRF-SXM INTEGRATION       PASS

echo RUN_STAGE MEM_SRF_ELABORATION
iverilog -g2012 -Wall -s tb_srf_mem_integration -o "%OUTDIR%\tb_srf_mem_integration.vvp" ^
  rtl\srf\core\stream_sr_superlane_col_dir.v ^
  rtl\srf\core\stream_sr_column_dir.v ^
  rtl\srf\core\stream_sr_direction_fabric.v ^
  rtl\srf\core\stream_sr_hemisphere_fabric.v ^
  rtl\srf\core\stream_sr_fabric.v ^
  rtl\mem\mem_bank_superlane_leaf.v ^
  rtl\mem\mem_bank_control_column.v ^
  rtl\mem\mem_logical_bank_column.v ^
  rtl\mem\mem_slice.v ^
  rtl\mem\mem_group.v ^
  rtl\mem\mem_hemisphere.v ^
  rtl\mem\mem_full.v ^
  rtl\integration\srf_mem_integration_top.v ^
  tb\integration\tb_srf_mem_integration.v > "%OUTDIR%\mem_srf_elaboration.log" 2>&1
if errorlevel 1 goto fail
echo MEM-SRF ELABORATION       PASS

echo RUN_STAGE COMBINED_ELABORATION
call :compile_full tb_srf_mem_sxm_integration tb\integration\tb_srf_mem_sxm_integration.v "%OUTDIR%\combined_elaboration.log"
if errorlevel 1 goto fail
echo COMBINED ELABORATION      PASS

echo RUN_STAGE LOOPBACK_E2E_ELABORATION
call :compile_full tb_mem_srf_sxm_loopback_e2e tb\e2e\tb_mem_srf_sxm_loopback_e2e.v "%OUTDIR%\loopback_elaboration.log"
if errorlevel 1 goto fail
echo LOOPBACK E2E ELABORATION  PASS

echo.
echo QUICK REGRESSION PASS
set "RESULT=0"
goto cleanup

:compile_full
iverilog -g2012 -Wall -s %~1 -o "%OUTDIR%\%~1.vvp" ^
  rtl\srf\core\stream_sr_superlane_col_dir.v ^
  rtl\srf\core\stream_sr_column_dir.v ^
  rtl\srf\core\stream_sr_direction_fabric.v ^
  rtl\srf\core\stream_sr_hemisphere_fabric.v ^
  rtl\srf\core\stream_sr_fabric.v ^
  rtl\mem\mem_bank_superlane_leaf.v ^
  rtl\mem\mem_bank_control_column.v ^
  rtl\mem\mem_logical_bank_column.v ^
  rtl\mem\mem_slice.v ^
  rtl\mem\mem_group.v ^
  rtl\mem\mem_hemisphere.v ^
  rtl\mem\mem_full.v ^
  rtl\sxm\sxm_command_decode.v ^
  rtl\sxm\sxm_transpose_superlane_leaf.v ^
  rtl\sxm\sxm_transpose_control_column.v ^
  rtl\sxm\sxm_transpose_result_buffer_array.v ^
  rtl\sxm\sxm_permute_engine.v ^
  rtl\sxm\sxm_slice.v ^
  rtl\sxm\sxm_full.v ^
  rtl\integration\srf_sxm_adapter.v ^
  rtl\integration\srf_mem_sxm_integration_top.v ^
  %~2 > %~3 2>&1
exit /b %ERRORLEVEL%

:fail
echo QUICK REGRESSION FAIL
set "RESULT=1"

:cleanup
if exist "%OUTDIR%" rmdir /s /q "%OUTDIR%"
popd
exit /b %RESULT%
