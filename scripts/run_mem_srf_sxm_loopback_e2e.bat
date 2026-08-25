@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim mkdir sim

echo RUN_STAGE MEM_SRF_SXM_LOOPBACK_E2E
iverilog -g2012 -Wall -s tb_mem_srf_sxm_loopback_e2e ^
  -o sim\tb_mem_srf_sxm_loopback_e2e.vvp ^
  rtl\srf\core\ftlpu_sr_superlane_col_dir.v ^
  rtl\srf\core\ftlpu_sr_column_dir.v ^
  rtl\srf\core\ftlpu_sr_direction_fabric.v ^
  rtl\srf\core\ftlpu_sr_hemisphere_fabric.v ^
  rtl\srf\core\ftlpu_sr_fabric.v ^
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
  tb\e2e\tb_mem_srf_sxm_loopback_e2e.v ^
  > sim\mem_srf_sxm_loopback_compile.log 2>&1
if errorlevel 1 goto compile_fail
findstr /I /C:"warning:" sim\mem_srf_sxm_loopback_compile.log >nul
if not errorlevel 1 goto warning_fail

vvp sim\tb_mem_srf_sxm_loopback_e2e.vvp ^
  > sim\mem_srf_sxm_loopback_regression.log 2>&1
if errorlevel 1 goto run_fail
type sim\mem_srf_sxm_loopback_regression.log
findstr /C:"TEST_FAIL" sim\mem_srf_sxm_loopback_regression.log >nul
if not errorlevel 1 goto run_fail
findstr /X /C:"MEM_SRF_SXM_LOOPBACK_E2E TEST_PASS" ^
  sim\mem_srf_sxm_loopback_regression.log >nul
if errorlevel 1 goto run_fail

echo ========================================
echo MEM_SRF_SXM_LOOPBACK_E2E_REGRESSION TEST_PASS
echo ========================================
popd
exit /b 0

:compile_fail
type sim\mem_srf_sxm_loopback_compile.log
echo MEM_SRF_SXM_LOOPBACK_E2E_COMPILE FAIL
goto fail

:warning_fail
type sim\mem_srf_sxm_loopback_compile.log
echo MEM_SRF_SXM_LOOPBACK_E2E_WARNING_CHECK FAIL
goto fail

:run_fail
type sim\mem_srf_sxm_loopback_regression.log
echo MEM_SRF_SXM_LOOPBACK_E2E_RUN FAIL

:fail
echo ========================================
echo MEM_SRF_SXM_LOOPBACK_E2E_REGRESSION TEST_FAIL
echo ========================================
popd
exit /b 1
