#!/usr/bin/env bash
set -euo pipefail
rg -q 'source_url' native/src/gdtf_runtime/registry/official_attributes.json
rg -q 'VideoEffect\(n\)Parameter\(n\)' native/src/gdtf_runtime/registry/official_attributes.json
rg -q 'docs/contract/gdtf' docs/peraviz-perastage-gdtf-contract.md
