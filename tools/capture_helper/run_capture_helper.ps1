$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "dsp_capture_helper.py"
python $script
