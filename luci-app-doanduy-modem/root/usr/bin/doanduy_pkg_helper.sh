#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# DOANDUY Dual Package Manager Helper (OpenWrt opkg <= 24.10 & apk >= 25.12/26+)
# [VERIFIED-GOLDEN: dual-opkg-apk-helper | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]

detect_pkg_mgr() {
	if command -v apk >/dev/null 2>&1 && [ -d /lib/apk/db ]; then
		printf 'apk'
	elif command -v opkg >/dev/null 2>&1; then
		printf 'opkg'
	elif command -v apk >/dev/null 2>&1; then
		printf 'apk'
	else
		printf 'none'
	fi
}

pkg_is_installed() {
	local pkg="$1" mgr
	[ -n "$pkg" ] || return 1
	mgr=$(detect_pkg_mgr)
	case "$mgr" in
		apk)
			apk info -e "$pkg" >/dev/null 2>&1
			return $?
			;;
		opkg)
			opkg status "$pkg" 2>/dev/null | grep -q '^Status:.* installed'
			return $?
			;;
		*)
			return 1
			;;
	esac
}

pkg_extract_archive() {
	local archive="$1" dest="$2"
	[ -f "$archive" ] && [ -n "$dest" ] || return 1
	mkdir -p "$dest" 2>/dev/null || return 1
	case "$archive" in
		*.apk)
			if command -v apk >/dev/null 2>&1; then
				apk extract --destination "$dest" "$archive" >/dev/null 2>&1 || \
					apk extract --allow-untrusted --destination "$dest" "$archive" >/dev/null 2>&1
				return $?
			fi
			tar -xzf "$archive" -C "$dest" 2>/dev/null
			return $?
			;;
		*.ipk)
			if tar -xzOf "$archive" ./data.tar.gz 2>/dev/null | tar -xz -C "$dest" 2>/dev/null; then
				return 0
			fi
			tar -xzOf "$archive" data.tar.gz 2>/dev/null | tar -xz -C "$dest" 2>/dev/null
			return $?
			;;
		*)
			return 1
			;;
	esac
}

pkg_install() {
	local target="$1" nodeps="$2" mgr
	[ -n "$target" ] || return 1
	mgr=$(detect_pkg_mgr)
	case "$mgr" in
		apk)
			if [ -f "$target" ]; then
				apk add --no-network --allow-untrusted "$target" 2>/dev/null || apk add --allow-untrusted "$target"
			else
				apk update >/dev/null 2>&1 || apk update --allow-untrusted >/dev/null 2>&1 || true
				if [ "$nodeps" = "1" ]; then
					apk add --allow-untrusted --no-scripts "$target" 2>/dev/null || apk add --allow-untrusted "$target"
				else
					apk add "$target" 2>/dev/null || apk add --allow-untrusted "$target"
				fi
			fi
			;;
		opkg)
			if [ -f "$target" ]; then
				if [ "$nodeps" = "1" ]; then
					opkg install --nodeps "$target"
				else
					opkg install "$target"
				fi
			else
				opkg update >/dev/null 2>&1 || true
				if [ "$nodeps" = "1" ]; then
					opkg install --nodeps "$target"
				else
					opkg install "$target"
				fi
			fi
			;;
		*)
			return 1
			;;
	esac
}

case "${1:-}" in
	manager)
		detect_pkg_mgr
		echo
		;;
	is-installed|check)
		pkg_is_installed "${2:-}"
		;;
	install)
		pkg_install "${2:-}" "${3:-0}"
		;;
	extract)
		pkg_extract_archive "${2:-}" "${3:-}"
		;;
	"")
		# Allow sourcing as a shell library when invoked with `. /usr/bin/doanduy_pkg_helper.sh`
		;;
	*)
		echo "Usage: $0 {manager|check <pkg>|install <pkg_or_file> [nodeps=0|1]|extract <file.ipk|file.apk> <dest>}" >&2
		exit 1
		;;
esac
# [/VERIFIED-GOLDEN]
