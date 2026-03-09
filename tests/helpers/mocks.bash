#!/usr/bin/env bash
# tests/helpers/mocks.bash — Mock command generators for test isolation

# mock_cmd <cmd> [exit_code] [stdout]
# Creates a stub executable that echoes stdout and exits with exit_code
mock_cmd() {
  local cmd="$1" exit_code="${2:-0}" stdout="${3:-}"
  local mock_dir="${BATS_TEST_TMPDIR}/mocks"
  mkdir -p "$mock_dir"
  cat > "${mock_dir}/${cmd}" <<EOF
#!/usr/bin/env bash
echo "${stdout}"
exit ${exit_code}
EOF
  chmod +x "${mock_dir}/${cmd}"
  export PATH="${mock_dir}:${PATH}"
}

# mock_cmd_with_args <cmd> [exit_code] [stdout]
# Like mock_cmd but records all arguments to a file for later assertion
mock_cmd_with_args() {
  local cmd="$1" exit_code="${2:-0}" stdout="${3:-}"
  local mock_dir="${BATS_TEST_TMPDIR}/mocks"
  mkdir -p "$mock_dir"
  cat > "${mock_dir}/${cmd}" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${BATS_TEST_TMPDIR}/${cmd}.args"
echo "${stdout}"
exit ${exit_code}
EOF
  chmod +x "${mock_dir}/${cmd}"
  export PATH="${mock_dir}:${PATH}"
}

# assert_mock_called_with <cmd> <expected_args>
# Checks that the mock was called with arguments containing the expected string
assert_mock_called_with() {
  local cmd="$1" expected="$2"
  local args_file="${BATS_TEST_TMPDIR}/${cmd}.args"
  assert [ -f "$args_file" ]
  run grep -F "$expected" "$args_file"
  assert_success
}
