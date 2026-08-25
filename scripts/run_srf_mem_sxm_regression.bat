@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim mkdir sim

echo RUN_STAGE RTL_SRF_MEM_SXM_COMBINED
iverilog -g2012 -Wall -s tb_srf_mem_sxm_integration ^
  -o sim\tb_srf_mem_sxm_integration.vvp ^
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
  tb\integration\tb_srf_mem_sxm_integration.v ^
  > sim\srf_mem_sxm_compile.log 2>&1
if errorlevel 1 goto compile_fail
findstr /I /C:"warning:" sim\srf_mem_sxm_compile.log >nul
if not errorlevel 1 goto warning_fail

vvp sim\tb_srf_mem_sxm_integration.vvp ^
  > sim\srf_mem_sxm_regression.log 2>&1
if errorlevel 1 goto run_fail
type sim\srf_mem_sxm_regression.log
findstr /C:"TEST_FAIL" sim\srf_mem_sxm_regression.log >nul
if not errorlevel 1 goto run_fail
findstr /X /C:"SRF_MEM_SXM_COMBINED_INTEGRATION TEST_PASS" ^
  sim\srf_mem_sxm_regression.log >nul
if errorlevel 1 goto run_fail

echo ========================================
echo SRF_MEM_SXM_COMBINED_REGRESSION TEST_PASS
echo ========================================
popd
exit /b 0

:compile_fail
type sim\srf_mem_sxm_compile.log
echo SRF_MEM_SXM_COMBINED_COMPILE FAIL
goto fail

:warning_fail
type sim\srf_mem_sxm_compile.log
echo SRF_MEM_SXM_COMBINED_WARNING_CHECK FAIL
goto fail

:run_fail
type sim\srf_mem_sxm_regression.log
echo SRF_MEM_SXM_COMBINED_INTEGRATION FAIL

:fail
echo ========================================
echo SRF_MEM_SXM_COMBINED_REGRESSION TEST_FAIL
echo ========================================
popd
exit /b 1
