#!/usr/bin/env bash
# tests/helpers/assertions.bash — Custom assertion helpers

# assert_line_contains <line_number> <substring>
# Check that a specific line in $output contains a substring
assert_line_contains() {
  local line_num="$1" substring="$2"
  local line="${lines[$line_num]}"
  if [[ "$line" != *"$substring"* ]]; then
    echo "Expected line $line_num to contain '$substring'" >&2
    echo "Actual: '$line'" >&2
    return 1
  fi
}

# assert_file_exists <path>
assert_file_exists() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Expected file to exist: $path" >&2
    return 1
  fi
}

# assert_file_contains <path> <string>
assert_file_contains() {
  local path="$1" string="$2"
  if ! grep -qF "$string" "$path" 2>/dev/null; then
    echo "Expected file '$path' to contain '$string'" >&2
    return 1
  fi
}

# assert_symlink_to <path> <target>
assert_symlink_to() {
  local path="$1" target="$2"
  if [[ ! -L "$path" ]]; then
    echo "Expected '$path' to be a symlink" >&2
    return 1
  fi
  local actual_target
  actual_target="$(readlink "$path")"
  if [[ "$actual_target" != "$target" ]]; then
    echo "Expected symlink '$path' -> '$target'" >&2
    echo "Actual target: '$actual_target'" >&2
    return 1
  fi
}
