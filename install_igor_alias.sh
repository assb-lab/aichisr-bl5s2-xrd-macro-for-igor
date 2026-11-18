#!/bin/sh
# AichiSR_BL5S2_XRD.ipf へのシンボリックリンク (エイリアス) を
# WaveMetrics の "Igor Procedures" フォルダに作る。
# Igor Procedures に置いたプロシージャは Igor 起動時に自動で読み込まれる。
#
#   ./install_igor_alias.sh           Igor Pro 8 に登録
#   ./install_igor_alias.sh 10        Igor Pro 10 に登録
#   ./install_igor_alias.sh -u [8]    登録を解除 (リンクだけ消す。本体は消さない)

set -eu

IPF_NAME="AichiSR_BL5S2_XRD.ipf"

uninstall=0
if [ "${1:-}" = "-u" ]; then
	uninstall=1
	shift
fi
version="${1:-8}"

src_dir=$(cd "$(dirname "$0")" && pwd)
src="$src_dir/$IPF_NAME"
dest_dir="$HOME/Documents/WaveMetrics/Igor Pro $version User Files/Igor Procedures"
dest="$dest_dir/$IPF_NAME"

if [ ! -d "$dest_dir" ]; then
	echo "error: folder not found: $dest_dir" >&2
	echo "       Igor Pro $version を一度起動すると作られます。" >&2
	exit 1
fi

if [ "$uninstall" -eq 1 ]; then
	if [ -L "$dest" ]; then
		rm "$dest"
		echo "removed: $dest"
	elif [ -e "$dest" ]; then
		echo "error: $dest はリンクではなく実ファイルなので消しません。" >&2
		exit 1
	else
		echo "not installed: $dest"
	fi
	exit 0
fi

if [ ! -f "$src" ]; then
	echo "error: $src が見つかりません。" >&2
	exit 1
fi

# 既存のリンクは張り直す。実ファイルがある場合は上書きしない。
if [ -L "$dest" ]; then
	rm "$dest"
elif [ -e "$dest" ]; then
	echo "error: $dest に実ファイルがあります。退避してから再実行してください。" >&2
	exit 1
fi

ln -s "$src" "$dest"
echo "linked: $dest"
echo "     -> $src"
echo "Igor Pro $version を再起動すると、メニュー \"AichiSR\" が出ます。"
