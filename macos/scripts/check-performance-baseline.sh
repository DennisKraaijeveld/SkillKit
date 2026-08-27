#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASELINE="${MACOS_DIR}/PerformanceBaseline.json"

for command in jq xcodebuild xcodegen xcrun; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "error: ${command} is required" >&2
    exit 2
  fi
done

expected_model="$(jq -r '.environment.modelIdentifier' "${BASELINE}")"
expected_arch="$(jq -r '.environment.architecture' "${BASELINE}")"
expected_os="$(jq -r '.environment.macOSBuild' "${BASELINE}")"
expected_xcode="$(jq -r '.environment.xcodeBuild' "${BASELINE}")"
actual_model="$(sysctl -n hw.model)"
actual_arch="$(uname -m)"
actual_os="$(sw_vers -buildVersion)"
actual_xcode="$(xcodebuild -version | awk '/Build version/ { print $3 }')"

if [[ "${actual_model}" != "${expected_model}" ||
      "${actual_arch}" != "${expected_arch}" ||
      "${actual_os}" != "${expected_os}" ||
      "${actual_xcode}" != "${expected_xcode}" ]]; then
  echo "error: the performance baseline belongs to a different environment" >&2
  echo "expected: ${expected_model} ${expected_arch}, macOS ${expected_os}, Xcode ${expected_xcode}" >&2
  echo "actual:   ${actual_model} ${actual_arch}, macOS ${actual_os}, Xcode ${actual_xcode}" >&2
  exit 2
fi

RESULT_DIR="$(mktemp -d /tmp/skillbook-performance.XXXXXX)"
RESULT_BUNDLE="${RESULT_DIR}/Performance.xcresult"
BUILD_LOG="${RESULT_DIR}/xcodebuild.log"
METRICS="${RESULT_DIR}/metrics.json"

cd "${MACOS_DIR}"
xcodegen generate >/dev/null

if ! xcodebuild \
  -project SkillKit.xcodeproj \
  -scheme "SkillKit Performance" \
  -configuration Performance \
  -destination "platform=macOS,arch=${actual_arch}" \
  -only-testing:SkillbookPerformanceTests/PerformanceTests \
  -resultBundlePath "${RESULT_BUNDLE}" \
  test CODE_SIGNING_ALLOWED=NO >"${BUILD_LOG}" 2>&1; then
  tail -n 120 "${BUILD_LOG}" >&2
  echo "result bundle: ${RESULT_BUNDLE}" >&2
  exit 1
fi

xcrun xcresulttool get test-results metrics \
  --path "${RESULT_BUNDLE}" \
  --compact >"${METRICS}"

failures=0
printf '%-62s %13s %13s %8s\n' "metric" "actual" "maximum" "result"

while IFS=$'\t' read -r test metric baseline_average max_regression unit; do
  actual="$(jq -r --arg test "${test}" --arg metric "${metric}" '
    .[]
    | select(.testIdentifier == $test)
    | .testRuns[0].metrics[]
    | select(.identifier == $metric)
    | (.measurements | add / length)
  ' "${METRICS}")"

  if [[ -z "${actual}" || "${actual}" == "null" ]]; then
    echo "error: missing ${metric} for ${test}" >&2
    failures=$((failures + 1))
    continue
  fi

  maximum="$(awk -v baseline="${baseline_average}" -v percent="${max_regression}" \
    'BEGIN { printf "%.12g", baseline * (1 + percent / 100) }')"

  if awk -v actual="${actual}" -v maximum="${maximum}" 'BEGIN { exit !(actual <= maximum) }'; then
    result="PASS"
  else
    result="FAIL"
    failures=$((failures + 1))
  fi

  label="${test#PerformanceTests/} ${metric#com.apple.dt.XCTMetric_}"
  printf '%-62s %10.4f %-2s %10.4f %-2s %8s\n' \
    "${label}" "${actual}" "${unit}" "${maximum}" "${unit}" "${result}"
done < <(jq -r '
  .tests
  | to_entries[]
  | .key as $test
  | .value
  | to_entries[]
  | [$test, .key, .value.baselineAverage, .value.maxPercentRegression, .value.unit]
  | @tsv
' "${BASELINE}")

echo "result bundle: ${RESULT_BUNDLE}"

if (( failures > 0 )); then
  exit 1
fi
