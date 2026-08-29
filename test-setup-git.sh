#!/usr/bin/env bash
set -euo pipefail

test_root=$(mktemp -d /tmp/setup-git.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/bin"

cat >"$test_root/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
    'auth status') [[ -f $GH_TEST_STATE ]] ;;
    'auth login') : >"$GH_TEST_STATE" ;;
    'auth setup-git') [[ -f $GH_TEST_STATE ]] ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$test_root/bin/gh"

printf 'Test User\ntest@example.com\n' | \
    HOME="$test_root/home" PATH="$test_root/bin:$PATH" \
    GH_TEST_STATE="$test_root/authenticated" ./setup-git.sh >/dev/null
[[ $(HOME="$test_root/home" git config --global user.name) == 'Test User' ]]
[[ $(HOME="$test_root/home" git config --global user.email) == test@example.com ]]
[[ -f $test_root/authenticated ]]
echo 'setup-git test passed'
