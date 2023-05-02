#!/bin/bash

if [ $# -ne 1 ]; then
    exit 1
fi

file=$1

# forbid ip
curl --silent https://ispip.clang.cn/all_cn_cidr.txt \
    --output "$file.tmp"
chmod 755 "$file.tmp"

while read line; do
    echo "deny $line;" >> $file
done < "$file.tmp"

rm -rf "$file.tmp"
